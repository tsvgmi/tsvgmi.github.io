# frozen_string_literal: true

Sequel.migration do
  change do
    create_table :songs do
      primary_key :id
      String :name,     null: false
      String :name_k,   unique: true, null: false
      String :artist,   index: true
      String :key
      String :lyric_url
      String :play_url
      String :preview
    end

    create_table :singers do
      primary_key :id
      String :name_k,   null: false
      String :singer,   index: true, null: false
      String :key
      String :style, index: true

      unique      %i[name_k singer]
      foreign_key :song_id, :songs
    end
  end
end
