if !exists('*RailsDetect') || !RailsDetect()
  finish
endif

call rails#ruby_setup()
