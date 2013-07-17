require 'sinatra'
require 'sinatra/activerecord'
require 'sinatra/flash'
require 'sinatra/r18n'
require "sinatra/config_file"
require 'xml/libxml'
require 'oj'
require 'builder'
require 'rest_client'

enable :sessions
set :erb, :trim => '-'

config_file 'config/config.yml'
R18n::I18n.default = settings.default_locale || "en"

#name, filename, orginal_filename, preset(xml), custom_preset(json)
class Collection < ActiveRecord::Base
  validates_presence_of :name
  
  #parses the xml file for author, description, version etc
  def parse_metadata
    parser = XML::Parser.string(self.preset)
    doc = parser.parse
    self.author = doc.root["author"]
    self.description = doc.root["description"]
    self.shortdescription = doc.root["shortdescription"]
    self.version = doc.root["version"]
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
 
  def xml_preset_to_json
    xml_array = to_preset_array
    json_array = []
    xml_array.each do | xml_leaf |
      json_array << parse_leaf(xml_leaf)     #xml_leaf is a Group or an Item
    end
    json_array.join(",")
    preset_json = Oj.dump(json_array)

    preset_json
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
      "values" => values, "default_value"=> element["default"], "link"=> element["href"], "id" => rand(32**8).to_s(32)}
    ele.delete_if {|k,v| v == nil}  #remove any empty key values, it reduces JSON size

    ele
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
  filename  = File.join(Dir.pwd,"tmp", orig_name)
  preset = tmpfile.read
  File.open(filename, "wb") { |f| f.write(preset) }
  FileUtils.chmod(0644, filename)

  collection = Collection.new(:name => params[:name].to_s, :original_filename => orig_name, :filename => filename, :preset => preset)
  collection.parse_metadata
  collection.custom_preset = collection.xml_preset_to_json
  collection.save

  flash[:info] = "Preset uploaded!"
  redirect  "/collection/#{collection.id}"
end

get '/collection/new' do
  @collection = Collection.new()
  erb :collection_new
end

post '/collection/new' do
  collection = Collection.new(params[:collection])
  if collection.save
    flash[:info] = "#{t.flash.created}"
    redirect "/collection/#{collection.id}"
  else
    flash[:error] = collection.errors.full_messages.join("<br />")

    @collection = Collection.new()
    erb :collection_new
  end
end


get '/collections' do
  @collections = Collection.find(:all, :order => "created_at desc")
  erb :collections
end

get '/collection' do
  redirect '/collections'
end
get '/collection/' do
  redirect '/collections'
end

get '/collection/:id.xml' do
  @collection = Collection.find(params[:id])
  @custom_preset = Oj.load(@collection.custom_preset)

  attachment  #<-- comment for inline render
  builder :preset
end

get '/collection/:id' do
  @collection = Collection.find(params[:id])
  erb :collection
end

put '/collection/:id' do
  @collection = Collection.find(params[:id])
  if @collection.update_attributes(params[:collection])
    flash[:info] = "#{t.flash.updated}"
    redirect "/collection/#{@collection.id}"
  else
    flash[:error] = @collection.errors.full_messages.join("<br />")
    @images = Dir.glob("public/icons/presets/*.png").sort_by { |x| x.downcase }
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
  flash[:info] = "#{t.flash.deleted}"
  redirect "/collections"
end

get '/collection/:id/validate' do
  @collection = Collection.find(params[:id])
  @valid = @collection.validate_xml_preset
  erb :collection_validate
end

get '/collection/:id/clone' do
  @collection = Collection.find(params[:id])
  erb :collection_clone
end

post '/collection/:id/clone' do
  existing_collection = Collection.find(params[:id])
  collection = existing_collection.dup
  collection.name =  "#{t.clone_prefix}  #{collection.name}"
  collection.save
  flash[:info] = "#{t.flash.cloned}"
  redirect  "/collection/#{collection.id}"
end

post '/data' do
p "poo"
p params.inspect
tmpfile = params[:uploadfile][:tempfile]
p tmpfile.read

end

get '/collection/:id/export_upload' do
  @collection = Collection.find(params[:id])
  erb :collection_export_upload
end

post '/collection/:id/export_upload' do
  @collection = Collection.find(params[:id])
  request = Rack::MockRequest.new(Sinatra::Application)
  
  xml_body = request.get("/collection/#{@collection.id.to_s}.xml").body
  p xml_body
  xml_file = File.join(Dir.pwd,"tmp", "#{@collection.id.to_s}_#{Process.pid}.xml")
  File.open(xml_file, "wb") { |f| f.write(xml_body) }
  
  begin
    response = RestClient.post("http://visualtags.herokuapp.com/data", 
   #response = RestClient.post(settings.hot_export_upload_url, 
              :uploadfile => File.new(xml_file, 'rb'),
              :utf8 => "&#x2713",
              :upload => {
                :name => @collection.name,
                :uptype => "preset"
              }
              )
  rescue => e
  
    redirect settings.hot_export_upload_url
  end

  redirect settings.hot_export_upload_url
end

