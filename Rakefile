require 'rake'
require 'rake/contrib/sshpublisher'

files = ['autoload/rails.vim', 'plugin/rails.vim', 'doc/rails.txt']

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
  Rake::SshFilePublisher.new("tpope.net","/var/www/railsvim",".","rails.zip","rails.vba").upload
end

desc "Install"
task :install do

  vimfiles = if ENV['VIMFILES']
               ENV['VIMFILES']
             elsif RUBY_PLATFORM =~ /(win|w)32$/
               File.expand_path("~/vimfiles")
             else
               File.expand_path("~/.vim")
             end

  puts "Installing rails.vim"
  files.each do |file|
    target_file = File.join(vimfiles, file)
    FileUtils.mkdir_p(File.dirname(target_file))
    FileUtils.cp(file, target_file)
    puts "  Copied #{file} to #{target_file}"
  end

  puts "Regenerating helptags"
  `vim -c 'helptags #{vimfiles}/doc' -c q 2> /dev/null`
  # '2> /dev/null' to suppress the following message:
  # "Vim: Warning: Output is not to a terminal"
  puts "  Processed #{vimfiles}/doc directory"

end

task 'zip' => 'rails.zip'
task 'vimball' => 'rails.vba'
task :default => [:zip, :vimball]
