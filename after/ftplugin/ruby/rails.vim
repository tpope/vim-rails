if (!exists('*RailsDetect') || !RailsDetect()) && expand('%:p') !~# '.*\ze[\/]\%(app\|config\|lib\|test\|spec\)[\/]'
  finish
endif

try
  call rails#ruby_setup()
catch /^Vim\%((\a\+)\)\=:E117:.*rails#ruby_setup/
endtry
