require 'sinatra'
require 'sinatra/activerecord'
require 'sinatra/flash'
require 'sinatra/r18n'
require "sinatra/config_file"
require 'xml/libxml'
require 'oj'
require 'builder'
require 'will_paginate'
require 'will_paginate/active_record'

enable :sessions
set :erb, :trim => '-'

config_file 'config/config.yml'
R18n::I18n.default = settings.default_locale || "en"

#name, filename, orginal_filename, preset(xml), custom_preset(json)
class Collection < ActiveRecord::Base
  validates_presence_of :name
  self.per_page = 40
  
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

def find_collection
  begin
    collection = Collection.find(params[:id]) 
  rescue ActiveRecord::RecordNotFound
    halt erb :not_found
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
  @collections = Collection.paginate(:page => params[:page]).order('created_at desc')
  erb :collections
end

get '/collection' do
  redirect '/collections'
end
get '/collection/' do
  redirect '/collections'
end

get '/collection/:id.xml' do
  @collection = find_collection
  @custom_preset = Oj.load(@collection.custom_preset)

  attachment  #<-- comment for inline render
  builder :preset
end

get '/collection/:id' do
  @collection = find_collection 
  erb :collection
end

put '/collection/:id' do
  @collection = find_collection 
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
  @collection = find_collection
  @images = Dir.glob("public/icons/presets/*.png").sort_by { |x| x.downcase }
  erb :collection_edit
end

delete '/collection/:id' do
  @collection = find_collection
  @collection.destroy
  flash[:info] = "#{t.flash.deleted}"
  redirect "/collections"
end

get '/collection/:id/validate' do
  @collection = find_collection
  @valid = @collection.validate_xml_preset
  erb :collection_validate
end

get '/collection/:id/clone' do
  @collection = find_collection
  erb :collection_clone
end

post '/collection/:id/clone' do
  existing_collection = find_collection
  collection = existing_collection.dup
  collection.name =  "#{t.clone_prefix}  #{collection.name}"
  collection.save
  flash[:info] = "#{t.flash.cloned}"
  redirect  "/collection/#{collection.id}"
end


get '/collection/:id/export_upload' do
  @collection = find_collection
  erb :collection_export_upload
end

post '/collection/:id/export_upload' do
  require 'mechanize'
  @collection = find_collection
  
  if @collection.custom_preset.empty?
    flash[:error] = "The preset has no items. Please add some items and tags to it"
    redirect "/collection/#{@collection.id}/export_upload"
    return true
  end
  
  if params[:email].empty? || params[:password].empty?
    flash[:error] = "Username and password required"
    redirect "/collection/#{@collection.id}/export_upload"
    return true
  end
  
  #render the preset and save it as temporary file
  request = Rack::MockRequest.new(Sinatra::Application)
  xml_body = request.get("/collection/#{@collection.id.to_s}.xml").body
  xml_file = File.join(Dir.pwd,"tmp", "#{@collection.id.to_s}_#{Process.pid}.xml")
  File.open(xml_file, "wb") { |f| f.write(xml_body) }
  
  #get mechanizing
  agent = Mechanize.new
  #login first
  login_page = agent.get(settings.hot_export["login_url"])
  login_form = login_page.form
  login_form["user[email]"] = params[:email]
  login_form["user[password]"] = params[:password]
  logged_in_page = agent.submit(login_form)
  
  if logged_in_page.form && logged_in_page.form.fields_with(:type => "email").length > 0
    flash[:error] = "Username and password not correct"
    redirect "/collection/#{@collection.id}/export_upload"
    return true
  end
  
  #upload
  upload_page = agent.get(settings.hot_export["upload_url"])
  upload_form = upload_page.form
  upload_form["upload[name]"] = @collection.name
  upload_form["upload[uptype]"] = "preset"
  upload_form.file_uploads.first.file_name = xml_file
  uploaded = agent.submit(upload_form)
  
  #logout probably wise, eh
  logged_out = agent.delete(settings.hot_export["logout_url"])

  redirect settings.hot_export["after_upload_url"]
end

