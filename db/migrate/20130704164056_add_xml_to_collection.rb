class AddXmlToCollection < ActiveRecord::Migration
  def up
    add_column :collections, :preset, :text
  end

  def down
    remove_column :collections, :preset
  end
end
