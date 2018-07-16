if !exists('*RailsDetect') || !RailsDetect()
  finish
endif

try
  call rails#ruby_setup()
catch /^E117:.*rails#ruby_setup/
endtry
