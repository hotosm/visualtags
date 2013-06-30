require 'sinatra'
require 'sinatra/activerecord'
require 'xml/libxml'

#name, filename, orginal_filename
class Collection < ActiveRecord::Base
  has_many :tags, :dependent => :destroy
  
  #code adapted from
  #https://github.com/hotosm/hot-exports/tree/master/webinterface/app/models/tag.rb
  def self.tags_from_xml(xml)
    tags = Hash.new
    p = XML::Parser.string(xml)
    doc = p.parse
    doc.root.namespaces.default_prefix='osm'
    items = doc.find('//osm:item')
    tags_array = []
    items.each do |item|
      item_geometrytype = self.type2geometrytype(item['type'])

      item.children.each do |child|
        if(!child['key'].nil?)
          tag = Tag.new()
          key = child['key']
          
          if !tags.has_key?(key)
            tag.key = key
            tags[key] = Hash.new
          end

          if child['type'].nil?
            geomlist = item_geometrytype
          else
            geomlist = self.type2geometrytype(child['type'])
          end
          tag.osm_type = geomlist.join(",")

          geomlist.each do |type|
            tags[key][type] = false
          end
          tags_array << tag if tag.key
        end
      end
    end
    return tags_array
  end

  #code adapted from
  #https://github.com/hotosm/hot-exports/tree/master/webinterface/app/models/tag.rb
  def self.type2geometrytype(type)
    geometrytype = Array.new

    if(type.nil?)
      geometrytype.push('point')
      geometrytype.push('line')
      geometrytype.push('polygon')
    else
      types = type.split(',')
      types.each do |type|
        if type == 'node'
          geometrytype.push('point')
        elsif type == 'way'
          geometrytype.push('line')
        elsif type == 'closedway'
          geometrytype.push('polygon')
        elsif type == 'relation'
          geometrytype.push('polygon')
        end
      end
    end

    return geometrytype
  end
end

#key, text, values, osm_type
class Tag < ActiveRecord::Base
  belongs_to :collection

  def to_s
    "#<Tag id:#{self.id}, key:#{self.key}, text:#{self.text}, osm_type:#{self.osm_type}>"
  end
end

get '/' do
  erb :home
end

get '/upload' do
  erb :upload
end

#new collection
post '/upload' do
  unless params[:name] && params[:file] && (tmpfile = params[:file][:tempfile]) && (orig_name = params[:file][:filename]) && File.extname(orig_name) == ".xml"
    redirect  '/upload'
  end
  filename  = File.join(Dir.pwd,"public/uploads", orig_name)
  File.open(filename, "wb") { |f| f.write(tmpfile.read) }
  FileUtils.chmod(0644, filename)

  collection = Collection.new(:name => params[:name].to_s, :original_filename => orig_name, :filename => filename)
  collection.save

  new_tags = Collection.tags_from_xml(File.read(filename))
  new_tags.each do | tag |
    collection.tags << tag
  end

  redirect  "/collection/#{collection.id}"
end

get '/collections' do
  @collections = Collection.find(:all, :order => "created_at desc")
  erb :collections
end

get '/collection/:id' do
  @collection = Collection.find(params[:id])
  erb :collection
end

put '/collection/:id' do
  @collection = Collection.find(params[:id])
  if @collection.update_attributes(params[:collection])
    redirect "/collection/#{@collection.id}"
  else
    erb :collection_edit
  end
end

get '/collection/:id/edit' do
  @collection = Collection.find(params[:id])
  erb :collection_edit
end

delete '/collection/:id' do
  @collection = Collection.find(params[:id])
  @collection.destroy
  redirect "/collections"
end

get '/collection/:id/tag/:tag_id' do
  @collection = Collection.find(params[:id])
  @tag = Tag.find(params[:tag_id])
  erb :tag
end

delete '/collection/:id/tag/:tag_id' do
  @collection = Collection.find(params[:id])
  @tag = Tag.find(params[:tag_id])

  @tag.destroy
  redirect  "/collection/#{@collection.id}"
end

get '/collection/:id/tag/:tag_id/edit' do
  @collection = Collection.find(params[:id])
  @tag = Tag.find(params[:tag_id])
  erb :tag_edit
end

put '/collection/:id/tag/:tag_id' do
  @collection = Collection.find(params[:id])
  @tag = Tag.find(params[:tag_id])
  if @tag.update_attributes(params[:tag])
    redirect "/collection/#{@collection.id}/tag/#{@tag.id}"
  else
    erb :tag_id
  end
end


