class CreateCollections < ActiveRecord::Migration
  def up
    create_table :collections do |t|
        t.string :name
        t.string :filename
        t.string :original_filename
        t.timestamps
    end
 
  end

  def down
    drop_table :collections
  end
end
