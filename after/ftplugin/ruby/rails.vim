if !exists('*RailsDetect') || !RailsDetect()
  finish
endif

try
  call rails#ruby_setup()
catch /^Vim\%((\a\+)\)\=:E117:.*rails#ruby_setup/
endtry
