class CreateLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :logs do |t|
      t.text :message
      # t.datetime :created_at

      t.timestamps
    end
  end
end
