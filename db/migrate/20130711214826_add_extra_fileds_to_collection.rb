class AddExtraFiledsToCollection < ActiveRecord::Migration
  def up
    add_column :collections, :author, :string
    add_column :collections, :shortdescription, :text
    add_column :collections, :description, :text
    add_column :collections, :version, :string
  end

  def down
    remove_column :collections, :author
    remove_column :collections, :shortdescription
    remove_column :collections, :description
    remove_column :collections, :version
  end
end
