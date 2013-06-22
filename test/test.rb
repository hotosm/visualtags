require File.expand_path '../app.rb', __FILE__
require 'test/unit'
require 'rack/test'

ENV['RACK_ENV'] = 'test'


class TagTest < Test::Unit::TestCase

  def test_can_create_a_tag
    t = Tag.new(:key => "horse")
    assert_not_nil t
  end
    
  def test_can_parse_xml
    xml = "<?xml version='1.0' encoding='UTF-8'?><presets xmlns='http://josm.openstreetmap.de/tagging-preset-1.0'><groups><group><item type='node'><text key='name'></text></item></group></groups></presets>"
    tt = Tag.from_xml(xml)
    puts tt
    assert_not_nil tt
  end

end

#class HomepageTest < Test::Unit::TestCase
#include Rack::Test::Methods
#def app() Sinatra::Application end

#def test_homepage
#get '/'
#assert last_response.ok?
#end
#end
