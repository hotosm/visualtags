class CreateTags < ActiveRecord::Migration
  def up
    create_table :tags do |t|
        t.string :key
        t.string :text
        t.text   :values
        t.string :osm_type
        t.integer :collection_id
        t.timestamps
    end
    Tag.create(key: "horse", text: "I love horses")
  end

  def down
    drop_table :tags
  end
end
