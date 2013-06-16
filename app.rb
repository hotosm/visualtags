require 'sinatra'
require 'sinatra/activerecord'
require 'xml/libxml'

class Collection < ActiveRecord::Base
    has_many :tags
end

class Tag < ActiveRecord::Base
    belongs_to :collection

def self.from_xml(xml)
      
      tags = Hash.new
      p = XML::Parser.string(xml)
      doc = p.parse
      doc.root.namespaces.default_prefix='fuzz'
      items = doc.find('//fuzz:item')

      items.each do |item|
         item_geometrytype = Tag.type2geometrytype(item['type'])

         # iterates each child with key attribute not nil
         item.children.each do |child|
            if(!child['key'].nil?)

               key = child['key']
               if !tags.has_key?(key)
                  tags[key] = Hash.new
               end

               if child['type'].nil?
                  geomlist = item_geometrytype
               else
                  geomlist = Tag.type2geometrytype(child['type'])
               end

               geomlist.each do |type|
                  tags[key][type] = false
               end

            end
         end
      end
      return tags
   end
   
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

get '/' do
  erb :home
end

get '/upload' do
  erb :form
end

post '/upload' do
    unless params[:name] && params[:file] && (tmpfile = params[:file][:tempfile]) && (orig_name = params[:file][:filename]) && File.extname(orig_name) == ".xml"
        redirect  '/upload'
    end
    filename  = File.join(Dir.pwd,"public/uploads", orig_name)
    File.open(filename, "wb") { |f| f.write(tmpfile.read) }
    FileUtils.chmod(0644, filename)
    
    @collection = Collection.new(:name => params[:name].to_s, :original_filename => orig_name, :filename => filename)
    @collection.save
        
    @tags = Tag.from_xml(File.read(filename))
    puts @tags.inspect
    
    'success'
end

enable :inline_templates

__END__
 
@@ form
<form action="" method="post" enctype="multipart/form-data">
  <p><label for="name">Name:</label>
     <input type="text" name="name" />
  </p>
  <p>
    <label for="file">File:</label>
    <input type="file" name="file">
  </p>
 
  <p>
    <input name="commit" type="submit" value="Upload" />
  </p>
</form>

@@ home
<a href="/upload">Upload new preset </a>
