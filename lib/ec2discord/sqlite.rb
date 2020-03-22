require 'sqlite3'

TB_DICTIONARY = "dictionary"
TB_USER = "user"

sql_create_table_dictionary = <<EOS
CREATE TABLE #{TB_DICTIONARY} (
  key                  TEXT PRIMARY KEY,
  value                TEXT,
  author_username      TEXT,
  author_discriminator INTEGER,
  locked               INTEGER,
  date                 INTEGER
)
EOS

sql_create_table_user = <<EOS
CREATE TABLE #{TB_USER} (
  username       TEXT,
  discriminator  INTEGER PRIMARY KEY,
  role           TEXT,
  date           INTEGER
)
EOS

class Ec2discordDB
	def initialize(filename="ec2discord.db")
		flag_first_run = !File.exist?(filename)
    @db = SQLLite3::Database.new(filename)
    @db.results_as_hash = true
    if flag_first_run then
      @db.execute(sql_create_table_dictionary)
      @db.execute(sql_create_table_user)
    end
	end

  def update_dictionary(key:, value:, author_username: null, author_discriminator: null, locked: false, overwrite: false)
    existing = db_exec_select_from_dictionary_where_key(key)
    unless existing.nil then
      if !overwrite then
        return "「#{key}」は既に登録されています。"
      elsif existing["locked"] && author_discriminator != existing["author_discriminator"] then
        return "「#{key}」は既に登録されていて，該当ユーザ以外の上書きが禁止されています。"
      else
        $log.debug("Dictionary: Overwite #{key}. Before: #{res['value']} (##{res['author_discriminator']}), After: #{value} (##{author_discriminator})")
        update = db_exec_update_dictionary(
          key: key,
          value: value,
          author_username: author_username,
          author_discriminator: author_discriminator,
          locked: locked,
          date: Time.now.to_i
          )
        if update.nil then
          $log.error("Dictionary: Fail to update new words (#{key}).")
          return "「#{key}」の上書きに失敗しました。管理者に連絡してください。"
        else
          return "「#{key}」を上書きしました。"
        end
      end
    else
      $log.debug("Dictionary: Create #{key}.")
      create = db_exec_insert_into_dictionary(
        key: key,
        value: value,
        author_username: author_username,
        author_discriminator: author_discriminator,
        locked: locked,
        date: Time.now.to_i
        )
      if create.nil then
        $log.error("Dictionary: Fail to register new words (#{key}).")
        return "「#{key}」の登録に失敗しました。管理者に連絡してください。"
      else
        return "「#{key}」を登録しました。"
      end
    end
  end

  def show_dictionary(key)
    h = db_exec_select_from_dictionary_where_key(key)
    if h.nil? then
      return "「#{key}」は登録されていません。"
    end
    h["value"]
  end

  def show_dictionary_all(author_discriminator: null)
    if author_discriminator == null then
      data = db_exec_select_from_dictionary
    else
      data = db_exec_select_from_dictionary_where_user(author_discriminator)
    end

    if data.nil then
      return "登録されている単語はありません。"
    else
      msg  = "```\n"
      msg += "| key | value |\n"
      msg += "|:----|:------|\n"
      data.each do |row|
        msg += "| #{row['key']} | #{row['value']} |\n"
      end
      msg += "```"
      return msg
    end
  end

  def delete_dictionary(key:, author_discriminator:)
    existing = db_exec_select_from_dictionary_where_key(key)
    if exsiting.nil then
      return "「#{key}」は登録されていませんので，削除の必要はありません。"
    else
      if existing["locked"] && author_discriminator != existing["author_discriminator"] then
        return "「#{key}」は該当ユーザ以外の削除が禁止されています。"
      else
        delete = db_exec_delete_from_dictionary(key: key)
        if delete.nil then
          $log.error("Dictionary: Fail to delete words (#{key}).")
          return "「#{key}」の削除に失敗しました。"
        else
          return "「#{key}」を削除しました。"
        end
      end
    end
  end

  private

  def db_exec_insert_into_dictionary(key:, value:, author_username:, author_discriminator:, locked:, date:)
    @db.execute("INSERT INTO #{TB_DICTIONARY} (key, value, author_username, author_discriminator, locked, date) VALUES('#{key}', '#{value}', '#{author_username}', '#{author_discriminator}', '#{locked}', '#{date}')")
  end

  def db_exec_select_from_dictionary
    @db.get_first_value("SELECT * FROM #{TB_DICTIONARY}")
  end

  def db_exec_select_from_dictionary_where_key(key="*")
    @db.get_first_value("SELECT * FROM #{TB_DICTIONARY} WHERE key='#{key}'")
  end

  def db_exec_select_from_dictionary_where_user(author_discriminator="*")
    @db.get_first_value("SELECT * FROM #{TB_DICTIONARY} WHERE author_discriminator='#{author_discriminator}'")
  end

  def db_exec_update_dictionary(key:, value:, author_username:, author_discriminator:, locked:, date:)
    @db.execute("UPDATE #{TB_DICTIONARY} SET value                = '#{value}'                WHERE key = '#{key}'")
    @db.execute("UPDATE #{TB_DICTIONARY} SET author_username      = '#{author_username}'      WHERE key = '#{key}'")
    @db.execute("UPDATE #{TB_DICTIONARY} SET author_discriminator = '#{author_discriminator}' WHERE key = '#{key}'")
    @db.execute("UPDATE #{TB_DICTIONARY} SET locked               = '#{locked}'               WHERE key = '#{key}'")
    @db.execute("UPDATE #{TB_DICTIONARY} SET date                 = '#{date}'                 WHERE key = '#{key}'")
  end

  def db_exec_delete_from_dictionary(key:)
    @db.execute("DELETE FROM #{TB_DICTIONARY} WHERE key = '#{key}'")
  end
end