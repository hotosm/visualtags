xml.presets :xmlns =>  "http://josm.openstreetmap.de/tagging-preset-1.0", :author => "Visual Tags Editor",
  :version => "0.0.1", :shortdescription => @collection.name + ". For use in HOT Exports Application",
  :description =>  @collection.name + ". A simple preset for use in the HOT exports application." do
  xml.group :name => "Simple Tags" do
    count = 1
    @collection.tags.group_by(&:osm_type).each do | osm_type, tags | 
    
      xml.item :name => "SimpleItem "+count.to_s, :icon => "", :type => osm_type do
     
        tags.each do | tag |
          xml.key :key => tag.key, :value => ""
        end #tag

      end #item
    count+=1
    end #group_by 



  end #group

end #presets
