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
  def access(id)
    blogpage = self.get("#{URL}&ct=#{id}")
    @httpStatuscode = blogpage.code
    @allArticle = blogpage.search('div .p-blog-article')
    @topArticle = @allArticle[0]
    @lastupdate = @topArticle.css('div .c-blog-article__date').inner_text.strip
  end
  def imgDL(path,isGetAllArticle)
    article = isGetAllArticle ? @allArticle : @topArticle 
    article.css('img').each do |image|
      src = image.attribute('src').value
      filepath = "#{path}#{::File.basename(src)}"
      ::URI.open(filepath,'wb') do |pass|
        ::URI.open(src) do |recieve|
          pass.write(recieve.read)
        end
      end
    end
  end
    
  URL = 'https://www.hinatazaka46.com/s/official/diary/member/list?ima=0000'
  attr_reader:lastupdate,:topArticle,:httpStatuscode
end

db = SQLite3::Database.new("main.db")
db.results_as_hash = true
db.busy_timeout = 6000

infolog = Logger.new(STDOUT)
errlog = Logger.new(STDERR)

db.execute('SELECT * FROM oshilist') do |row|
  blog = HinataBlog.new
  begin
    blog.access(row['id'])
  rescue => e
    errlog.error(e.message.to_s)
    break
  end
  unless blog.httpStatuscode == '200'
    errlog.error("Scraping failed HTTPStatuscode:#{blog.httpStatuscode}")
    break
  end
  if row['lastupdate']==blog.lastupdate
    infolog.info("There was no blog update:#{memberID.invert[row['id']]}")
    next
  end
  isGetAllArticle = row['lastupdate']==nil ? true : false
  blog.imgDL(row['path'],isGetAllArticle)
  updateSQL = 'UPDATE oshilist SET lastupdate = :lastupdate WHERE id = :id;'
  db.execute(updateSQL,:lastupdate => blog.lastupdate,:id => row['id'])
  infolog.info("Scraping was successful:#{memberID.invert[row['id']]}")
end
