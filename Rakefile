# $Id$

require 'rake'
require 'rake/contrib/sshpublisher'

files = ['plugin/rails.vim', 'doc/rails.txt']

desc "Make zip file"
file 'rails.zip' => files do |t|
  File.unlink t.name if File.exists?(t.name)
  system('zip','-q',t.name,*t.prerequisites)
end

desc "Make vimball"
file 'rails.vba' => files do |t|
  File.unlink t.name if File.exists?(t.name)
  File.open(t.name,"w") do |out|
    out.puts '" Vimball Archiver by Charles E. Campbell, Jr., Ph.D.'
    out.puts 'UseVimball'
    out.puts 'finish'
    t.prerequisites.each do |name|
      File.open(name) do |file|
        file.each_line {}
        out.puts name
        out.puts file.lineno
        file.rewind
        file.each_line {|l|out.puts l}
      end
    end
  end
end

task :publish => [:zip,:vimball] do
  Rake::SshFilePublisher.new("tpope.us","/var/www/railsvim",".","rails.zip","rails.vba").upload
end

task 'zip' => 'rails.zip'
task 'vimball' => 'rails.vba'
task :default => [:zip, :vimball]
