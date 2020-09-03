require 'mechanize'
require 'open-uri'
require 'sqlite3'
require 'logger'
require 'json'

memberID = Array.new
File.open('./memberId.json') do |j|
  memberID = JSON.load(j)
end

class HinataBlog < Mechanize
  def initialize(id)
    super
    blogpage = self.get("#{URL}&ct=#{id}")
    @httpStatuscode = blogpage.code
    @allArticles = blogpage.search('div .p-blog-article')
    @update_time_datas = Array.new
    @allArticles.each do |article|
      @update_time_datas.push(self.getUpdateTime(article))
    end
    @lastupdate = self.getUpdateTime(@allArticles[0])
  end
  def imgDL(path,articleNum)
    articleNum.times do |num|
      article = @allArticles[num]
      article.css('img').each do |image|
        src = image.attribute('src').value
        next if src == ''
        article_date = article.css('div .c-blog-article__date').inner_text.strip
        filename = "#{article_date.gsub(/( |:)+/,'_')}_#{::File.basename(src)}"
        filepath = "#{path}#{filename}"
        ::URI.open(filepath,'wb') do |pass|
          ::URI.open(src) do |recieve|
            pass.write(recieve.read)
          end
        end
      end
    end
  end  
  URL = 'https://www.hinatazaka46.com/s/official/diary/member/list?ima=0000'
  attr_reader:lastupdate,:update_time_datas,:httpStatuscode
  private
  def getUpdateTime(article)
    return article.css('div .c-blog-article__date').inner_text.strip
  end
end

db = SQLite3::Database.new("main.db")
db.results_as_hash = true
db.busy_timeout = 6000

infolog = Logger.new(STDOUT)
errlog = Logger.new(STDERR)

db.execute('SELECT * FROM oshilist') do |row|
  begin
    blog = HinataBlog.new(row['id'])
  rescue => e
    errlog.error(e.message.to_s)
    break
  end
  unless blog.httpStatuscode == '200'
    errlog.error("Scraping failed HTTPStatuscode:#{blog.httpStatuscode}")
    break
  end
  case row['lastupdate']
  when blog.lastupdate
    infolog.info("There was no blog update:#{memberID.invert[row['id']]}")
    next
  when nil
    articleNum = blog.update_time_datas.length
  else
    articleNum = blog.update_time_datas.index(row['lastupdate'])+1
  end
  blog.imgDL(row['path'],articleNum)
  updateSQL = 'UPDATE oshilist SET lastupdate = :lastupdate WHERE id = :id;'
  db.execute(updateSQL,:lastupdate => blog.lastupdate,:id => row['id'])
  infolog.info("Scraping was successful:#{memberID.invert[row['id']]}")
end
