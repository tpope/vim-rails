# rails.vim

Remember when everybody and their mother was using TextMate for Ruby on
Rails development?  Well if it wasn't for rails.vim, we'd still be in
that era.  So shut up and pay some respect.  And check out these
features:

* Easy navigation of the Rails directory structure.  `gf` considers
  context and knows about partials, fixtures, and much more.  There are
  two commands, `:A` (alternate) and `:R` (related) for easy jumping
  between files, including favorites like model to schema, template to
  helper, and controller to functional test.  For more advanced usage,
  `:Rmodel`, `:Rview`, `:Rcontroller`, and several other commands are
  provided.  `:help rails-navigation`

* Enhanced syntax highlighting.  From `has_and_belongs_to_many` to
  `distance_of_time_in_words`, it's here.  For easy completion of these
  long method names, `'completefunc'` is set to enable syntax based
  completion on CTRL-X CTRL-U.

* Interface to rake.  Use `:Rake` to run the current test, spec, or
  feature.  Use `:.Rake` to do a focused run of just the method,
  example, or scenario on the current line.  `:Rake` can also run
  arbitrary migrations, load individual fixtures, and more.
  `:help rails-rake`

* Interface to the `rails` command.  Generally, use `:Rails console` to
  call `rails console` or `script/console`.  Most commands have wrappers
  with additional features: `:Rgenerate controller Blog` generates a
  blog controller and edits `app/controllers/blog_controller.rb`.
  `:help rails-scripts`

* Partial and concern extraction.  In a view, `:Rextract {file}`
  replaces the desired range (typically selected in visual line mode)
  with `render '{file}'`, which is automatically created with your
  content.  In a model or controller, a concern is created, with the
  appropriate `include` declaration left behind.
  `:help rails-:Rextract`

* Integration with other plugins.  `:Rtree` spawns
  [NERDTree.vim](https://github.com/scrooloose/nerdtree).  If
  [dbext.vim](http://www.vim.org/scripts/script.php?script_id=356) is
  installed, it will be transparently configured to reflect
  `database.yml`.  Users of
  [abolish.vim](https://github.com/tpope/vim-abolish) get pluralize and
  tableize coercions, and users of
  [bundler.vim](https://github.com/tpope/vim-bundler) get a smattering of
  features.  `:help rails-integration`

## Installation

If you don't have a preferred installation method, I recommend
installing [pathogen.vim](https://github.com/tpope/vim-pathogen), and
then simply copy and paste:

    cd ~/.vim/bundle
    git clone git://github.com/tpope/vim-rails.git
    git clone git://github.com/tpope/vim-bundler.git


You don't strictly need [bundler.vim][], but it helps.

Once help tags have been generated, you can view the manual with
`:help rails`.

[bundler.vim]: https://github.com/tpope/vim-bundler

## FAQ

> I installed the plugin and started Vim.  Why does only the `:Rails`
> command exist?

This plugin cares about the current file, not the current working
directory.  Edit a file from a Rails application.

> I opened a new tab.  Why does only the `:Rails` command exist?

This plugin cares about the current file, not the current working
directory.  Edit a file from a Rails application.  You can use the `:RT`
family of commands to open a new tab and edit a file at the same time.

> Can I use rails.vim to edit Rails engines?

It's not supported, but if you `touch config/environment.rb` in the root
of the engine, things should mostly work.

> Can I use rails.vim to edit other Ruby projects?

I wrote [rake.vim](https://github.com/tpope/vim-rake) for exactly that
purpose.  It activates for any project with a `Rakefile` that's not a
Rails application.

> What Rails versions are supported?

All of them.  A few features like syntax highlighting tend to reflect the
latest version only.

> Rake is slow.  How about making `:Rake` run
> `testrb`/`rspec`/`cucumber` directly instead of `rake`?

Well then it wouldn't make sense to call it `:Rake`, now, would it?
Maybe one day I'll add a separate `:Run` command or something.  In the
meantime, here's how you can set up `:make` to run the current test:

    autocmd FileType cucumber compiler cucumber | setl makeprg=cucumber\ \"%:p\"
    autocmd FileType ruby
          \ if expand('%') =~# '_test\.rb$' |
          \   compiler rubyunit | setl makeprg=testrb\ \"%:p\" |
          \ elseif expand('%') =~# '_spec\.rb$' |
          \   compiler rspec | setl makeprg=rspec\ \"%:p\" |
          \ else |
          \   compiler ruby | setl makeprg=ruby\ -wc\ \"%:p\" |
          \ endif
    autocmd User Bundler
          \ if &makeprg !~# 'bundle' | setl makeprg^=bundle\ exec\  | endif

## Self-Promotion

Like rails.vim? Follow the repository on
[GitHub](https://github.com/tpope/vim-rails) and vote for it on
[vim.org](http://www.vim.org/scripts/script.php?script_id=1567).  And if
you're feeling especially charitable, follow [tpope](http://tpo.pe/) on
[Twitter](http://twitter.com/tpope) and
[GitHub](https://github.com/tpope).

## License

Copyright (c) Tim Pope.  Distributed under the same terms as Vim itself.
See `:help license`.
