require File.expand_path '../../app.rb', __FILE__
require 'test/unit'
require 'rack/test'
require 'oj'
set :environment, :test
ENV['RACK_ENV'] = 'test'

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

end


class HomepageTest < Test::Unit::TestCase
  include Rack::Test::Methods
  def app() Sinatra::Application end

  def test_homepage
    get '/'
    assert last_response.ok?
  end
end
