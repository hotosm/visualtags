class AddDefaultToCollection < ActiveRecord::Migration
  def up
    add_column :collections, :default, :boolean
  end

  def down
    remove_column :collections, :default
  end
end
