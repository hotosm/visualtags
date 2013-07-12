def render_node(xml, node)
  if node["type"] == "item"
    item(xml, node)
  end
  if node["type"] == "group"
    group(xml, node)
  end
end

def group(xml, node)
  xml.group :name => node["name"], :icon => node["icon"] do
    if node["children"]
      node["children"].each do | child |
        render_node(xml, child)
      end
    end
  end
end

def item(xml, node)
  xml.item :name => node["name"], :icon => node["icon"], :type => node["geo_type"] do
    node["item"].each do | tag |
      render_tag(xml, tag)
    end
  end
end

#label,space,key,text,combo,multiselect,check, optional
def render_tag(xml, tag)
  if tag["name"] == "optional"
    xml.optional do
      tag["children"].each do | child_tag |
        render_tag(xml, child_tag)
      end
    end
  end
  if tag["name"] == "label"
    xml.label :text => tag["text"]
  end
  if tag["name"] == "key"
    xml.key :key => tag["key"], :value => tag["value"]
  end
  if tag["name"] == "text"
    xml.text :key => tag["key"], :text => tag["text"]
  end
  if tag["name"] == "space"
    xml.space
  end
  if tag["name"] == "combo"
    xml.combo :key => tag["key"], :text => tag["text"], :values => tag["values"]
  end
  if tag["name"] == "multiselect"
    xml.multiselect :key => tag["key"], :text => tag["text"], :values => tag["values"]
  end
  if tag["name"] == "check"
    tag["default_value"] = "off" unless tag["default_value"] == "on"
    xml.check :key => tag["key"], :text => tag["text"], :default => tag["default_value"]
  end
  if tag["name"] == "link"
    xml.link :href => tag["link"]
  end
end
 
xml.presets :xmlns =>  "http://josm.openstreetmap.de/tagging-preset-1.0", :author => @collection.author,
  :version => @collection.version, :shortdescription => @collection.shortdescription,
  :description =>  @collection.description do
  
  @custom_preset.each do | node |
    render_node(xml, node)
  end

end #presets
