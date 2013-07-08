class AddCustomPresetToCollection < ActiveRecord::Migration
  def up
    add_column :collections, :custom_preset, :text
  end

  def down
    remove_column :collections, :custom_preset
  end
end
