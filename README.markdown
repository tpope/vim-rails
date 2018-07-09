# rails.vim

This is a massive (in a good way) Vim plugin for editing Ruby on Rails
applications.

* Easy navigation of the Rails directory structure.  `gf` considers
  context and knows about partials, fixtures, and much more.  There are
  two commands, `:A` (alternate) and `:R` (related) for easy jumping
  between files, including favorites like model to schema, template to
  helper, and controller to functional test.  Commands like `:Emodel`,
  `:Eview`, `:Econtroller`, are provided to `:edit` files by type, along
  with `S`, `V`, and `T` variants for `:split`, `:vsplit`, and
  `:tabedit`.  Throw a bang on the end (`:Emodel foo!`) to automatically
  create the file with the standard boilerplate if it doesn't exist.
  `:help rails-navigation`

* Enhanced syntax highlighting.  From `has_and_belongs_to_many` to
  `distance_of_time_in_words`, it's here.

* Interface to the `rails` command.  Generally, use `:Rails console` to
  call `rails console`.  Many commands have wrappers with additional features:
  `:Generate controller Blog` generates a blog controller and loads the
  generated files into the quickfix list, and `:Runner` wraps `rails runner`
  and doubles as a direct test runner.  `:help rails-exec`

* Default task runner.  Use `:Rails` (with no arguments) to run the current
  test, spec, or feature.  Use `:.Rails` to do a focused run of just the
  method, example, or scenario on the current line.  `:Rails` can also run
  arbitrary migrations, load individual fixtures, and more.
  `:help rails-default-task`

* Partial and concern extraction.  In a view, `:Extract {file}`
  replaces the desired range (typically selected in visual line mode)
  with `render '{file}'`, which is automatically created with your
  content.  In a model or controller, a concern is created, with the
  appropriate `include` declaration left behind.
  `:help rails-:Extract`

* Fully customizable. Define "projections" at the global, app, or gem
  level to define navigation commands and override the alternate file,
  default rake task, syntax highlighting, and more.
  `:help rails-projections`.

* Integration with other plugins.  If [dispatch.vim][] is installed, `:Rails`
  and other command wrappers will use it for asynchronous execution.  Users of
  [dadbod.vim](https://github.com/tpope/vim-dadbod) and
  [dbext](http://www.vim.org/script.php?script_id=356) get easy access to
  their application's database.  Users of
  [abolish.vim](https://github.com/tpope/vim-abolish) get pluralize and
  tableize coercions, and users of [bundler.vim][] get a smattering of
  features.   `:help rails-integration`

## Installation

If you don't have a preferred installation method, I recommend
installing [pathogen.vim](https://github.com/tpope/vim-pathogen), and
then simply copy and paste:

    cd ~/.vim/bundle
    git clone https://github.com/tpope/vim-rails.git
    vim -u NONE -c "helptags vim-rails/doc" -c q

While not strictly necessary, [bundler.vim][] and [dispatch.vim][] are highly
recommended.

[bundler.vim]: https://github.com/tpope/vim-bundler
[dispatch.vim]: https://github.com/tpope/vim-dispatch

## FAQ

> I installed the plugin and started Vim.  Why does only the `:Rails`
> command exist?

This plugin cares about the current file, not the current working
directory.  Edit a file from a Rails application.

> I opened a new tab.  Why does only the `:Rails` command exist?

This plugin cares about the current file, not the current working directory.
Edit a file from a Rails application.  You can use `:AT` and the `:T` family
of commands to open a new tab and edit a file at the same time.

> Can I use rails.vim to edit Rails engines?

It's not supported, but if you `touch config/environment.rb` in the root
of the engine, things should mostly work.

> Can I use rails.vim to edit other Ruby projects?

I wrote [rake.vim](https://github.com/tpope/vim-rake) for exactly that
purpose.  It activates for any project with a `Rakefile` that's not a
Rails application.

> What Rails versions are supported?

All of them, although you may notice a few minor breakages if you dip below
3.0.  A few features like syntax highlighting tend to reflect the latest
version only.

> Didn't rails.vim used to handle indent settings?

It got yanked after increasing contention over JavaScript.  Check out
[sleuth.vim](https://github.com/tpope/vim-sleuth).

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
