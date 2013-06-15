require 'sinatra'
require 'sinatra/activerecord'

class Tag < ActiveRecord::Base

end

get '/' do
  "Hello, world"
end
