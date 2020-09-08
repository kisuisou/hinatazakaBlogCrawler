require 'sqlite3'
require 'thor'
require 'json'

class Setup < Thor
  package_name 'hinatazakaBlogCrawler'
  default_command :about
  no_commands do
    def setupDB
      @database = SQLite3::Database.new('main.db')
      @memberIDs = Array.new
      File.open('./memberId.json') do |j|
        @memberIDs = JSON.load(j)
      end
      searchTableSQL = "SELECT * FROM sqlite_master WHERE type='table' AND name='oshilist';" 
      createTableSQL = <<-SQL
        CREATE TABLE oshilist(
          id integer primary key,
          path text,
          lastupdate text
        );
      SQL
      if @database.execute(searchTableSQL).length==0
        @database.execute(createTableSQL)
      end
      @database.busy_timeout = 6000
    end
    def getDBdata(id = nil)
      @database.results_as_hash = true
      if id == nil
        result = @database.execute('SELECT * FROM oshilist')
      else
        result = @database.execute('SELECT * FROM oshilist WHERE id = ?;',id)
      end
      @database.results_as_hash = false
      return result
    end
    def pathValidation
      loop do
        puts '写真をDLするディレクトリの絶対パスを入力してください'
        print '--->'
        inputPath = ::STDIN.gets.chomp
        if !(%r|\A/([^\\:*<>?"\|/]+/)*[^\\:*<>?"\|/]*\Z| =~ inputPath)
          puts 'パスが不正です'
          next
        elsif !(::Dir.exist?(inputPath))
          puts 'ディレクトリが存在しません'
          next
        elsif !(::File.ftype(inputPath) == 'directory')
          puts 'ディレクトリではありません'
          next
        end
         return inputPath[-1] == '/' ? inputPath : inputPath << '/'
        break
      end
    end
    def writeDB(memberID,memberName,inputPath,isRewrite)
      writeSQL = isRewrite ? 'UPDATE oshilist SET path = :path WHERE id = :id' : 'INSERT INTO oshilist(id,path) VALUES(:id,:path)'
      loop do
        print "メンバー:#{memberName}\nDLするディレクトリ:#{inputPath}\n以上の内容で登録しますか?(y/n)--->"
        writeDB_YN = ::STDIN.gets.chomp
        if /y/i =~ writeDB_YN
          @database.execute(writeSQL,:id => memberID,:path => inputPath)
          puts "データベースへの書き込みが終了しました。"
          break
        elsif /n/i =~ writeDB_YN
          break
        else
          next
        end
      end
    end
    def pickUpDBdata(message)
      settingNum = 0
      memberNames = Array.new
      memberName = String.new
      memberID = nil
      dbData = self.getDBdata()
      if dbData.length ==0
        puts 'データが登録されていません'
        exit
      end
      puts message
      dbData.each.with_index(1) do |hash,i|
        name = @memberIDs.invert[hash['id']]
        memberNames.push(name)
        puts "#{i}):#{name}"
        settingNum += 1
      end
      loop do
        print '--->'
        inputNum = ::STDIN.gets.chomp
        if !(/^[0-9]+$/ =~ inputNum)
          puts '数値を入力してください'
          next
        elsif inputNum.to_i > settingNum || inputNum.to_i <= 0
          puts "1～#{settingNum}を入力してください"
          next
        else
          memberName = memberNames[inputNum.to_i-1]
          memberID = @memberIDs[memberName]
          break
        end
      end
      return {memberName:memberName,memberID:memberID}
    end
    def deleteDB(id=nil)
      if id == nil
        @database.execute('DELETE FROM oshilist;')
      else
        @database.execute('DELETE FROM oshilist WHERE id = ?',id)
      end
    end
    def printHeader
      puts '==============================================================='
      puts '      メンバー     |     DLパス      |     最終更新日時        '
      puts '==============================================================='
    end
  end
  desc 'about','このツールの概要を表示します'
  def about
  message = <<~EOS
    =====================
    hinatazakaBlogCrawler
    =====================\n
    このツールは日向坂46のブログから画像をスクレイピングするCLIツールです。
    使用手順は以下の通りです。\n
    1)このスクリプトでスクレイピングするブログのメンバーとDLするディレクトリのパスを登録する。
    2)scrape.rbを実行する。\n
    scrape.rbをcron等に設定することにより定期的なスクレイピングも可能です。
    このスクリプトの使用方法はhelpコマンドで確認できます。
  EOS
  puts message
  end  
  desc 'add','スプレイピングするブログを追加します'
  def add
    self.setupDB
    puts "スクレイピングを行うブログを追加します。\nメンバーの左に書かれた番号を入力してください。"
    memberNames = @memberIDs.keys
    memberNames.each.with_index(1) do |value,i|
      puts "#{i}):#{value}"
    end
    memberName = String.new
    memberID = nil
    loop do
      print '--->'
      inputNum = ::STDIN.gets
      if !(inputNum =~ /^[0-9]+$/)
        puts "数値を入力してください"
        next
      elsif memberNames.length < inputNum.to_i || inputNum.to_i <= 0 
        puts "1～#{memberNames.length}の値を入力してください"
        next
      else
        memberName = memberNames[inputNum.to_i-1]
        memberID = @memberIDs[memberName]
        if self.getDBdata(memberID).length != 0
          puts "#{memberName}はすでに登録されています"
          next
        end
        break
      end
    end
    inputPath = self.pathValidation
    self.writeDB(memberID,memberName,inputPath,false)
 end
  desc 'edit','保存先のディレクトリを変更します'
  def edit
    self.setupDB
    data = self.pickUpDBdata('画像の保存先を変更します。どのメンバーの設定を変更しますか？')
    inputPath = self.pathValidation
    writeDB(data[:memberID],data[:memberName],inputPath,true)
  end
  desc 'delete','設定を削除します'
  method_option :all,aliases: '-a', desc: 'すべての設定を削除します'
  method_option :force,aliases: '-f',desc: '確認をスキップして強制的にコマンドを実行します'  
  def delete
    self.setupDB
    if options.all == 'all' && options.force == 'force'
      self.deleteDB()
      puts 'すべての設定を削除しました'
    elsif options.all == 'all'
      loop do
        print 'すべての設定を削除します。本当に削除しますか?(y/n)--->'
        deleteAllYN = ::STDIN.gets.chomp
        if /y/i =~ deleteAllYN
          self.deleteDB()
          puts 'すべての設定を削除しました。'
        elsif /n/i =~ deleteAllYN
          break
        else
          next
        end
      end
    else
      data = self.pickUpDBdata('設定を削除します。どのメンバーの設定を削除しますか？')
      if options.force == 'force'
        self.deleteDB(data[:memberID])
        puts "#{data[:memberName]}の設定を削除しました。"
      else
        loop do
          print "#{data[:memberName]}の設定を削除します。本当に削除しますか？(y/n)--->"
          deleteYN = ::STDIN.gets.chomp
          if /y/i =~ deleteYN
            self.deleteDB(data[:memberID])
            puts 'データベースから削除されました。'
            break
          elsif /n/i =~ deleteYN
            break
          else
            next
          end
        end
      end
    end
  end
  desc 'show [メンバーの名前]','現在登録されている設定とブログの最終更新日時を表示します'
  def show(name = nil)
    self.setupDB
    dbdata = self.getDBdata()
    memberNames = Array.new
    if dbdata.length == 0
      puts 'データが登録されていません'
    else
      if name == nil
        self.printHeader
        dbdata.each do |hash|
          puts "  #{@memberIDs.invert[hash['id']]}   |   #{hash['path']}   |   #{hash['lastupdate']}" 
        end
      elsif @memberIDs.include?(name)
        memberID = @memberIDs[name]
        dbdata_search = self.getDBdata(memberID)
        if dbdata_search.length == 0
          puts "#{name}は登録されていません"
        else
          self.printHeader
          puts "  #{@memberIDs.invert[dbdata_search[0]['id']]}   |   #{dbdata_search[0]['path']}   |   #{dbdata_search[0]['lastupdate']}"
        end 
      else
        puts "'#{name}'は日向坂46のメンバーではありません"
      end
    end
  end
end

Setup.start(ARGV)
