ENV['RACK_ENV'] = 'test'
require File.expand_path '../../app.rb', __FILE__
require 'test/unit'
require 'rack/test'
require 'oj'
set :environment, :test

class CollectionTest < Test::Unit::TestCase
 def setup
    xml = File.read("test/simple-test.xml")
    @collection = Collection.new(:name => "test") 
    @collection.preset = xml
 end


  def test_can_parse_xml_to_json
    preset_json = @collection.xml_preset_to_json
    json = Oj.load(preset_json)
    assert_not_nil preset_json
    assert_equal(json[0]["name"], "Testing")
    assert_equal(json[0]["children"][0]["name"], "Baker")
  end

  def test_can_parse_metadata
    assert_nil @collection.author
    @collection.parse_metadata
    assert_equal @collection.author, "Tim Waters"
  end

  def test_can_validate_valid
    results = @collection.validate_xml_preset
    assert_equal TrueClass, results.class
    assert results # and that it passes
  end

  def test_can_validate_invalid
    xml = File.read("test/invalid_josm.xml")
    invalid = Collection.new(:name => "invalid")
    invalid.preset = xml
    results = invalid.validate_xml_preset 
    
    assert_equal String, results.class
    assert_equal "Error: Element", results[0..13]
    assert results.include?"group"
  end
  
  def test_copy
    @collection.save
    cloned = @collection.copy("copy of  #{@collection.name}")
    cloned.save
    assert_not_equal cloned.id, @collection.id
    assert cloned.name.include? "copy of "
  end
  
  def test_copy_default
    @collection.default = true
    @collection.save
    cloned = @collection.copy("copy of  #{@collection.name}")
    cloned.save

    assert_not_equal @collection.default, cloned.default
  end

end


class HomepageTest < Test::Unit::TestCase
  include Rack::Test::Methods
  def app() Sinatra::Application end
  
   def setup
    xml = File.read("test/simple-test.xml")
    @collection = Collection.new(:name => "test") 
    @collection.preset = xml
    @collection.save
   end
 
   def teardown
    @collection.destroy
   end
  

  def test_homepage
    get '/'
    assert last_response.ok?
  end
  
  def test_new
    get '/collection/new'
    assert last_response.ok?
    assert last_response.body.include?('collection_form')
  end
  
  def test_create
    post '/collection/new', :collection => {:name => "test create name", :custom_preset => ""}
    follow_redirect!
    assert last_response.ok?
    collection_id = Collection.last.id
    assert_equal "http://example.org/collection/"+collection_id.to_s+"/edit", last_request.url
  end
  
  def test_edit
    get "/collection/#{@collection.id}/edit"
    assert last_response.ok?
    assert last_response.body.include?('collection_form')
  end
  
  def test_edit_default
    @collection.default = true
    @collection.save
    get "/collection/#{@collection.id}/edit"
    follow_redirect!
    assert_equal "http://example.org/collection/"+@collection.id.to_s, last_request.url
    assert last_response.body.include?("flash error")
  end
  
  def test_post_clone
    post "/collection/#{@collection.id}/clone"
    follow_redirect!
    new_collection = Collection.last
    assert_equal "http://example.org/collection/"+new_collection.id.to_s, last_request.url
    assert new_collection.name.include?("Copy of ")
  end
  
  def test_post_clone_default
    @collection.default = true
    @collection.save
    post "/collection/#{@collection.id}/clone"
    follow_redirect!
    new_collection = Collection.last
    assert_equal "http://example.org/collection/"+new_collection.id.to_s, last_request.url
    assert new_collection.name.include?("Copy of ")
    assert_not_equal new_collection.default, @collection.default
  end
  
  
  
end
