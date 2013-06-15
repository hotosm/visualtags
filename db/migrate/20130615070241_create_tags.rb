class CreateTags < ActiveRecord::Migration
  def up
    create_table :tags do |t|
        t.string :title
        t.timestamps
    end
    Tag.create(title: "test tag title1")
  end

  def down
    drop_table :tags
  end
end
