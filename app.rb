require 'sinatra'
require 'sinatra/activerecord'
require 'xml/libxml'

#name, filename, orginal_filename, preset(xml), custom_preset(json)
class Collection < ActiveRecord::Base
  has_many :tags, :dependent => :destroy
  
  def to_preset_array()
    parser = XML::Parser.string(self.preset)
    doc = parser.parse
    doc.root.namespaces.default_prefix='osm'
    #items = doc.find('//osm:preset')
    a = []
    doc.root.children.each do | child |
      if child.name == "group" || child.name == "item"
        a << child
      end unless child.empty?
    end

    return a
  end


  def validate_preset()
    return Collection.validate_preset(self.preset)
  end

  def self.validate_preset(preset)
    parser = XML::Parser.string(preset)
    document = parser.parse
    
    schema_document = XML::Document.file("lib/tagging-preset.xsd")
    schema = XML::Schema.document(schema_document)
    begin
      return document.validate_schema(schema)  #true if validates, otherwise exceptions raised
    rescue LibXML::XML::Error => e
      error = e.to_s
      return error
    end
  end
  
  #code adapted from
  #https://github.com/hotosm/hot-exports/tree/master/webinterface/app/models/tag.rb
  def self.tags_from_xml(xml)
    tags = Hash.new
    parser = XML::Parser.string(xml)
    doc = parser.parse
    doc.root.namespaces.default_prefix='osm'
    items = doc.find('//osm:item')
    tags_array = []
    items.each do |item|
      itype = item["type"] || ""
      item_geometrytype = itype.split(',') 

      item.children.each do |child|
        if(!child['key'].nil?)
          key = child['key']
          
          if !tags.has_key?(key)
            tags[key] = Hash.new
          end

          if child['type'].nil?
            geomlist = item_geometrytype
          else
            #this is rare, I think, and may not be allowed by the xsd
            geomlist = item["type"].split(',')
          end

          geomlist.each do |type|
            tags[key][type] = false
          end
         
        end
      end
    end
    tags.each do | tag |
        tags_array << Tag.new(:key => tag[0], :osm_type => tag[1].keys.sort().join(","))
    end

    return tags_array
  end


end

#key, text, values, osm_type
class Tag < ActiveRecord::Base
  belongs_to :collection

  def to_s
    "#<Tag id:#{self.id}, key:#{self.key}, text:#{self.text}, osm_type:#{self.osm_type}>"
  end
  
end

set :erb, :trim => '-'

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
  preset = tmpfile.read
  File.open(filename, "wb") { |f| f.write(preset) }
  FileUtils.chmod(0644, filename)

  collection = Collection.new(:name => params[:name].to_s, :original_filename => orig_name, :filename => filename, :preset => preset)
  collection.save

  new_tags = Collection.tags_from_xml(File.read(filename))
  collection.tags = new_tags  #saved to the collection

  redirect  "/collection/#{collection.id}"
end

get '/collections' do
  @collections = Collection.find(:all, :order => "created_at desc")
  erb :collections
end

get '/collection/:id.xml' do
  @collection = Collection.find(params[:id])

  attachment  #<-- comment for inline render
  builder :simple_preset
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

get '/collection/:id/validate' do
  @collection = Collection.find(params[:id])
  @valid = @collection.validate_preset
  erb :collection_validate
end

get '/collection/:id/tag' do
  @collection = Collection.find(params[:id])
  @tag = Tag.new

  erb :tag_new
end

post '/collection/:id/tag' do
  @collection = Collection.find(params[:id])
  @tag = Tag.new(params[:tag])
  @collection.tags << @tag
  
  redirect "/collection/#{@collection.id}/tag/#{@tag.id}"
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
  @action = "edit"
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


