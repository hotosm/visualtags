require 'sinatra'
require 'sinatra/activerecord'
require 'sinatra/flash'
require 'xml/libxml'
require 'oj'
require 'builder'

enable :sessions
set :erb, :trim => '-'

#name, filename, orginal_filename, preset(xml), custom_preset(json)
class Collection < ActiveRecord::Base
  has_many :tags, :dependent => :destroy
  
  #parses the xml file for author, description, version etc
  def parse_metadata
    parser = XML::Parser.string(self.preset)
    doc = parser.parse
    self.author = doc.root["author"]
    self.description = doc.root["description"]
    self.shortdescription = doc.root["shortdescription"]
    self.version = doc.root["version"]

    return true
  end

  def validate_xml_preset()
    return Collection.validate_xml_preset(self.preset)
  end

  def self.validate_xml_preset(preset)
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
          item_geometrytype.each do |type|
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

  def xml_preset_to_json
    xml_array = to_preset_array
    json_array = []
    xml_array.each do | xml_leaf |
      json_array << parse_leaf(xml_leaf)     #xml_leaf is a Group or an Item
    end
    json_array.join(",")
    #preset_json = Oj.dump(json_array)

    #preset_json
    json_array
  end

  private

  #converts the uploaded preset to an array of nodes
  def to_preset_array()
    parser = XML::Parser.string(self.preset)
    doc = parser.parse
    doc.root.namespaces.default_prefix='osm'
    #items = doc.find('//osm:preset')
    preset_array = []
    doc.root.children.each do | child |
      if child.name == "group" || child.name == "item"
        preset_array << child
      end unless child.empty?
    end

    preset_array
  end

  # Parses an XML element of either Item or Group
  def parse_leaf(xml_leaf)
    if xml_leaf.name == "item" || xml_leaf.name == "group"
      leaf = {"name" => xml_leaf["name"], "type" => xml_leaf.name, "icon" => xml_leaf["icon"],
        "geo_type" => xml_leaf["type"], "id" => rand(32**8).to_s(32) }
      leaf["item"] = parse_item(xml_leaf) if xml_leaf.name == "item"
    end
    if xml_leaf.name == "group" && xml_leaf.children?
      leaf["children"] = []
      xml_leaf.children.each do | c |
        if c.name == "item" || c.name == "group"
          leaf["children"] << parse_child(c)
        end
      end
    end

    leaf
  end

  #parses an item and extracts the tag / form elements from it
  def parse_item(item)
    elements = []
    item.each_element do | ce |
      element = {}
      element = parse_element(ce)
      if ce.name == "optional"
        optional_items = []
        ce.each_element do | opt |
          optional_items << parse_element(opt)
        end
        element["children"] = optional_items
      end
      elements << element
    end

    elements
  end

  #parses a child of an Item or Group.
  #if it's a group, the child has children of its own
  def parse_child(child)
    if child.name == "item" || child.name == "group"
      child_hash = {"name" => child["name"], "type" => child.name, "icon" => child["icon"],
        "geo_type" => child["type"], "id" => rand(32**8).to_s(32) }
      child_hash["item"] = parse_item(child) if child.name == "item"
    end
    if child.name == "group" && child.children?
      child_hash["children"] = []
      child.children.each do | c |
        if c.name == "item" || c.name == "group"
          child_hash["children"] << parse_child(c)
        end
      end
    end

    child_hash
  end

  def parse_element(element)
    values = element["values"] || nil
    if element.name == "combo" && element.children.length > 0 && values.nil?
      values = []
      element.each_element do |list_item |
        values << list_item["value"]
      end
      values = values.join(",")
    end
    ele = {"name"=> element.name, "key"=> element["key"], "text" => element["text"], "value"=> element["value"],
      "values" => values, "default_value"=> element["default"], "link"=> element["href"]}
    ele.delete_if {|k,v| v == nil}  #remove any empty key values, it reduces JSON size

    ele
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
  preset = tmpfile.read
  File.open(filename, "wb") { |f| f.write(preset) }
  FileUtils.chmod(0644, filename)

  collection = Collection.new(:name => params[:name].to_s, :original_filename => orig_name, :filename => filename, :preset => preset)
  collection.parse_metadata
  collection.save

  new_tags = Collection.tags_from_xml(File.read(filename))
  collection.tags = new_tags  #saved to the collection
  flash[:info] = "Collection uploaded!"
  redirect  "/collection/#{collection.id}"
end

get '/collections' do
  @collections = Collection.find(:all, :order => "created_at desc")
  erb :collections
end

get '/collection' do
  redirect '/collections'
end

get '/collection/:id.xml' do
  @collection = Collection.find(params[:id])

  attachment  #<-- comment for inline render
  builder :simple_preset
end

get '/collection/:id.xml2' do
  @collection = Collection.find(params[:id])
  @custom_preset = Oj.load(@collection.custom_preset)

  #attachment  #<-- comment for inline render
  builder :preset
end

get '/collection/:id' do
  @collection = Collection.find(params[:id])
  erb :collection
end

put '/collection/:id' do
  @collection = Collection.find(params[:id])
  if @collection.update_attributes(params[:collection])
    flash[:info] = "Collection updated!"
    redirect "/collection/#{@collection.id}"
  else
    erb :collection_edit
  end
end

get '/collection/:id/edit' do
  @collection = Collection.find(params[:id])
  @images = Dir.glob("public/icons/presets/*.png").sort_by { |x| x.downcase }
  erb :collection_edit
end

delete '/collection/:id' do
  @collection = Collection.find(params[:id])
  @collection.destroy
  flash[:info] = "Collection deleted!"
  redirect "/collections"
end

get '/collection/:id/validate' do
  @collection = Collection.find(params[:id])
  @valid = @collection.validate_xml_preset
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
  flash[:info] = "New tag reated!"

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
  flash[:info] = "Tag deleted!"
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
    flash[:info] = "Tag updated!"
    redirect "/collection/#{@collection.id}/tag/#{@tag.id}"
  else
    erb :tag_id
  end
end


