hi def link rubyEntity                      rubyMacro
hi def link rubyEntities                    rubyMacro
hi def link rubyExceptionMacro              rubyMacro
hi def link rubyValidation                  rubyMacro
hi def link rubyCallback                    rubyMacro
hi def link rubyRakeMacro                   rubyMacro
hi def link rubyTestMacro                   rubyMacro
hi def link rubyMacro                       Macro
hi def link rubyRoute                       rubyControl
hi def link rubySchema                      rubyControl
hi def link rubyResponse                    rubyControl
hi def link rubyAction                      rubyControl
hi def link rubyUrlHelper                   rubyHelper
hi def link rubyViewHelper                  rubyHelper
hi def link rubyTestHelper                  rubyHelper
hi def link rubyUserAssertion               rubyAssertion
hi def link rubyAssertion                   rubyException
hi def link rubyTestAction                  rubyControl
hi def link rubyHelper                      Function

let s:has_app = exists('*RailsDetect') && RailsDetect()
let s:path = tr(expand('%:p'), '\', '/')

if s:path =~# '\v/app/%(channels|controllers|helpers|jobs|mailers|models)/.*\.rb$|/app/views/'
  syn keyword rubyHelper logger
endif

if s:path =~# '/app/models/.*_observer\.rb$'
  syn keyword rubyMacro observe

elseif s:path =~# '/app/models/.*\.rb$'
  syn keyword rubyMacro accepts_nested_attributes_for attr_readonly attribute enum serialize store store_accessor
  syn keyword rubyMacro default_scope scope
  syn keyword rubyEntity belongs_to has_one composed_of
  syn keyword rubyEntities has_many has_and_belongs_to_many
  syn keyword rubyCallback before_validation after_validation
  syn keyword rubyCallback before_create before_destroy before_save before_update
  syn keyword rubyCallback  after_create  after_destroy  after_save  after_update
  syn keyword rubyCallback around_create around_destroy around_save around_update
  syn keyword rubyCallback after_commit after_create_commit after_update_commit after_destroy_commit after_rollback
  syn keyword rubyCallback after_find after_initialize after_touch
  syn keyword rubyValidation validates validates_acceptance_of validates_associated validates_confirmation_of validates_each validates_exclusion_of validates_format_of validates_inclusion_of validates_length_of validates_numericality_of validates_presence_of validates_absence_of validates_size_of validates_with
  syn keyword rubyValidation validates_associated validates_uniqueness_of
  syn keyword rubyMacro validate has_secure_password has_secure_token has_one_attached has_many_attached
endif

if s:path =~# '/app/jobs/.*\.rb$'
  syn keyword rubyMacro queue_as
  syn keyword rubyExceptionMacro rescue_from retry_on discard_on
  syn keyword rubyCallback before_enqueue around_enqueue after_enqueue before_perform around_perform after_perform
endif

if s:path =~# '/app/helpers/.*_helper\.rb$\|/app/views/'
  syn keyword rubyViewHelper
        \ action_name asset_pack_path asset_path asset_url atom_feed audio_path audio_tag audio_url auto_discovery_link_tag
        \ button_tag button_to
        \ cache cache_fragment_name cache_if cache_unless capture cdata_section check_box check_box_tag collection_check_boxes collection_radio_buttons collection_select color_field color_field_tag compute_asset_extname compute_asset_host compute_asset_path concat content_tag content_tag_for controller controller_name controller_path convert_to_model cookies csp_meta_tag csrf_meta_tag csrf_meta_tags current_cycle cycle
        \ date_field date_field_tag date_select datetime_field datetime_field_tag datetime_local_field datetime_local_field_tag datetime_select debug distance_of_time_in_words distance_of_time_in_words_to_now div_for dom_class dom_id
        \ email_field email_field_tag escape_javascript escape_once excerpt
        \ favicon_link_tag field_set_tag fields fields_for file_field file_field_tag flash font_path font_url form_for form_tag form_with
        \ grouped_collection_select grouped_options_for_select
        \ headers hidden_field hidden_field_tag highlight
        \ image_alt image_pack_tag image_path image_submit_tag image_tag image_url
        \ j javascript_cdata_section javascript_include_tag javascript_pack_tag javascript_path javascript_tag javascript_url
        \ l label label_tag link_to link_to_if link_to_unless link_to_unless_current localize
        \ mail_to month_field month_field_tag
        \ number_field number_field_tag number_to_currency number_to_human number_to_human_size number_to_percentage number_to_phone number_with_delimiter number_with_precision
        \ option_groups_from_collection_for_select options_for_select options_from_collection_for_select
        \ params password_field password_field_tag path_to_asset path_to_audio path_to_font path_to_image path_to_javascript path_to_stylesheet path_to_video phone_field phone_field_tag pluralize preload_link_tag provide public_compute_asset_path
        \ radio_button radio_button_tag range_field range_field_tag raw render request request_forgery_protection_token reset_cycle response
        \ safe_concat safe_join sanitize sanitize_css search_field search_field_tag select_date select_datetime select_day select_hour select_minute select_month select_second select_tag select_time select_year session simple_format strip_links strip_tags stylesheet_link_tag stylesheet_pack_tag stylesheet_path stylesheet_url submit_tag
        \ t tag telephone_field telephone_field_tag text_area text_area_tag text_field text_field_tag time_ago_in_words time_field time_field_tag time_select time_tag time_zone_options_for_select time_zone_select to_sentence translate truncate
        \ url_field url_field_tag url_for url_to_asset url_to_audio url_to_font url_to_image url_to_javascript url_to_stylesheet url_to_video utf8_enforcer_tag
        \ video_path video_tag video_url
        \ week_field week_field_tag word_wrap
  syn match rubyViewHelper '\<select\>\%(\s*{\|\s*do\>\|\s*(\=\s*&\)\@!'
  syn match rubyViewHelper '\<\%(content_for\w\@!?\=\|current_page?\)'
  syn match rubyViewHelper '\.\@<!\<\(h\|html_escape\|u\|url_encode\)\>'
  if s:path =~# '_[^\/]*$'
    syn keyword rubyViewHelper local_assigns
  endif
endif

if s:path =~# '/app/controllers/.*\.rb$'
  syn keyword rubyHelper params request response session headers cookies flash
  syn keyword rubyMacro protect_from_forgery skip_forgery_protection
  syn match   rubyMacro '\<respond_to\>\ze[( ] *[:*]'
  syn match   rubyResponse '\<respond_to\>\ze[( ] *\%([&{]\|do\>\)'
  syn keyword rubyResponse render head redirect_to redirect_back respond_with send_data send_file
endif

let b:rails_path = s:path
if s:path =~# '/app/controllers/.*\.rb$\|/app/mailers/.*\.rb$\|/app/models/.*_mailer\.rb$'
  syn keyword rubyHelper render_to_string
  syn keyword rubyCallback before_action append_before_action prepend_before_action after_action append_after_action prepend_after_action around_action append_around_action prepend_around_action skip_before_action skip_after_action skip_action
  syn keyword rubyMacro helper helper_attr helper_method layout
  syn keyword rubyExceptionMacro rescue_from
endif

if s:path =~# '/app/mailers/.*\.rb$\|/app/models/.*_mailer\.rb$'
  syn keyword rubyResponse mail render
  syn match   rubyResponse "\<headers\>"
  syn match   rubyHelper "\<headers\[\@="
  syn keyword rubyHelper params attachments
  syn keyword rubyMacro default
  syn keyword rubyMacro register_interceptor register_interceptors register_observer register_observers
endif

if s:path =~# '/app/\w\+/concerns/.*\.rb$'
  syn keyword rubyMacro included class_methods
endif

if s:path =~# '\v/app/%(controllers|helpers|mailers).*\.rb$|/app/views/' ||
      \ s:has_app && rails#buffer().type_name('test-controller', 'test-integration', 'test-system', 'spec-request', 'spec-feature', 'cucumber')
  syn keyword rubyUrlHelper url_for polymorphic_path polymorphic_url edit_polymorphic_path edit_polymorphic_url new_polymorphic_path new_polymorphic_url
endif

if s:path =~# '/db/migrate/.*\.rb$\|/db/schema\.rb$'
  syn keyword rubySchema create_table change_table drop_table rename_table create_join_table drop_join_table
  syn keyword rubySchema add_column rename_column change_column change_column_default change_column_null remove_column remove_columns
  syn keyword rubySchema add_foreign_key remove_foreign_key
  syn keyword rubySchema add_timestamps remove_timestamps
  syn keyword rubySchema add_reference remove_reference add_belongs_to remove_belongs_to
  syn keyword rubySchema add_index remove_index rename_index
  syn keyword rubySchema enable_extension reversible revert
  syn keyword rubySchema execute transaction
endif

if s:path =~# '\.rake$\|/Rakefile[^/]*$'
  syn match rubyRakeMacro '^\s*\zs\%(task\|file\|namespace\|desc\)\>\%(\s*=\)\@!'
endif

if s:path =~# '/config/routes\>.*\.rb$'
  syn keyword rubyRoute resource resources collection member new nested shallow
  syn keyword rubyRoute match get put patch post delete root mount
  syn keyword rubyRoute scope controller namespace constraints defaults
  syn keyword rubyRoute concern concerns
  syn keyword rubyRoute direct resolve
  syn keyword rubyHelper redirect
endif

if s:path =~# '/test\%(/\|/.*/\)test_[^\/]*\.rb$\|/test/.*_test\.rb$\|/features/step_definitions/.*\.rb$'
  syn keyword rubyAssertion refute     refute_empty     refute_equal     refute_in_delta     refute_in_epsilon     refute_includes     refute_instance_of     refute_kind_of     refute_match    refute_nil     refute_operator     refute_predicate     refute_respond_to     refute_same
  syn keyword rubyAssertion assert     assert_empty     assert_equal     assert_in_delta     assert_in_epsilon     assert_includes     assert_instance_of     assert_kind_of     assert_match    assert_nil     assert_operator     assert_predicate     assert_respond_to     assert_same
  syn keyword rubyAssertion assert_not assert_not_empty assert_not_equal assert_not_in_delta assert_not_in_epsilon assert_not_includes assert_not_instance_of assert_not_kind_of assert_no_match assert_not_nil assert_not_operator assert_not_predicate assert_not_respond_to assert_not_same
  syn keyword rubyAssertion assert_raises         assert_send     assert_throws
  syn keyword rubyAssertion assert_nothing_raised assert_not_send assert_nothing_thrown
  syn keyword rubyAssertion assert_raise assert_block assert_mock assert_output assert_raise_with_message assert_silent
  syn keyword rubyAssertion flunk
endif

if s:path =~# '/spec/.*_spec\.rb$'
  syn match rubyTestHelper '\<subject\>'
  syn match rubyTestMacro '\<\%(let\|given\)\>!\='
  syn match rubyTestMacro '\<subject\>!\=\ze\s*\%([({&:]\|do\>\)'
  syn keyword rubyTestMacro before after around background setup teardown
  syn keyword rubyTestMacro context describe feature shared_context shared_examples shared_examples_for containedin=rubyKeywordAsMethod
  syn keyword rubyTestMacro it example specify scenario include_examples include_context it_should_behave_like it_behaves_like
  syn keyword rubyComment xcontext xdescribe xfeature containedin=rubyKeywordAsMethod
  syn keyword rubyComment xit xexample xspecify xscenario
endif
if s:path =~# '/spec/.*_spec\.rb$\|/features/step_definitions/.*\.rb$'
  syn keyword rubyAssertion pending skip expect is_expected expect_any_instance_of allow allow_any_instance_of
  syn keyword rubyTestHelper described_class
  syn keyword rubyTestHelper double instance_double class_double object_double
  syn keyword rubyTestHelper spy instance_spy class_spy object_spy
  syn keyword rubyTestAction stub_const hide_const
endif

if !s:has_app
  finish
endif

if rails#buffer().type_name('test')
  if !empty(rails#app().user_assertions())
    exe "syn keyword rubyUserAssertion ".join(rails#app().user_assertions())
  endif
  syn keyword rubyTestMacro test setup teardown
  syn keyword rubyAssertion assert_difference assert_no_difference
  syn keyword rubyAssertion assert_changes    assert_no_changes
  syn keyword rubyAssertion assert_emails assert_enqueued_emails assert_no_emails assert_no_enqueued_emails
  syn keyword rubyTestAction travel travel_to travel_back
endif
if rails#buffer().type_name('test-controller', 'test-integration', 'test-system')
  syn keyword rubyAssertion assert_response assert_redirected_to assert_template assert_recognizes assert_generates assert_routing
endif
if rails#buffer().type_name('test-helper', 'test-controller', 'test-integration', 'test-system')
  syn keyword rubyAssertion assert_dom_equal assert_dom_not_equal assert_select assert_select_encoded assert_select_email
  syn keyword rubyTestHelper css_select
endif
if rails#buffer().type_name('test-system')
  syn keyword rubyAssertion     assert_matches_css     assert_matches_selector     assert_matches_xpath
  syn keyword rubyAssertion     refute_matches_css     refute_matches_selector     refute_matches_xpath
  syn keyword rubyAssertion assert_not_matches_css assert_not_matches_selector assert_not_matches_xpath
  syn keyword rubyAssertion    assert_button    assert_checked_field    assert_content    assert_css    assert_current_path    assert_field    assert_link    assert_select    assert_selector    assert_table    assert_text    assert_title    assert_unchecked_field    assert_xpath
  syn keyword rubyAssertion assert_no_button assert_no_checked_field assert_no_content assert_no_css assert_no_current_path assert_no_field assert_no_link assert_no_select assert_no_selector assert_no_table assert_no_text assert_no_title assert_no_unchecked_field assert_no_xpath
  syn keyword rubyAssertion    refute_button    refute_checked_field    refute_content    refute_css    refute_current_path    refute_field    refute_link    refute_select    refute_selector    refute_table    refute_text    refute_title    refute_unchecked_field    refute_xpath
endif

if rails#buffer().type_name('spec-controller')
  syn keyword rubyTestMacro render_views
  syn keyword rubyTestHelper assigns
endif
if rails#buffer().type_name('spec-helper')
  syn keyword rubyTestAction assign
  syn match rubyTestHelper '\<helper\>'
  syn match rubyTestMacro '\<helper\>!\=\ze\s*\%([({&:]\|do\>\)'
endif
if rails#buffer().type_name('spec-view')
  syn keyword rubyTestAction assign render
  syn keyword rubyTestHelper rendered
endif

if rails#buffer().type_name('test', 'spec')
  syn keyword rubyTestMacro fixtures use_transactional_tests use_instantiated_fixtures
  syn keyword rubyTestHelper file_fixture
endif
if rails#buffer().type_name('test-controller', 'test-integration', 'spec-controller', 'spec-request')
  syn match   rubyTestAction '\.\@<!\<\%(get\|post\|put\|patch\|delete\|head\|process\)\>'
  syn match   rubyTestAction '\<follow_redirect!'
  syn keyword rubyTestAction get_via_redirect post_via_redirect
  syn keyword rubyTestHelper request response flash session cookies fixture_file_upload
endif
if rails#buffer().type_name('test-system', 'spec-feature', 'cucumber')
  syn keyword rubyTestHelper body current_host current_path current_scope current_url current_window html response_headers source status_code title windows
  syn keyword rubyTestHelper page text
  syn keyword rubyTestHelper all field_labeled find find_all find_button find_by_id find_field find_link first
  syn keyword rubyTestAction evaluate_script execute_script go_back go_forward open_new_window save_and_open_page save_and_open_screenshot save_page save_screenshot switch_to_frame switch_to_window visit window_opened_by within within_element within_fieldset within_frame within_table within_window
  syn match   rubyTestAction "\<reset_session!"
  syn keyword rubyTestAction attach_file check choose click_button click_link click_link_or_button click_on fill_in select uncheck unselect
endif

syn keyword rubyAttribute class_attribute
syn keyword rubyAttribute attr_internal attr_internal_accessor attr_internal_reader attr_internal_writer
syn keyword rubyAttribute cattr_accessor cattr_reader cattr_writer mattr_accessor mattr_reader mattr_writer
syn keyword rubyAttribute thread_cattr_accessor thread_cattr_reader thread_cattr_writer thread_mattr_accessor thread_mattr_reader thread_mattr_writer
syn keyword rubyMacro alias_attribute concern concerning delegate delegate_missing_to with_options

let s:special = {
      \ '[': '\>\[\@=',
      \ ']': '\>[[.]\@!',
      \ '{': '\>\%(\s*{\|\s*do\>\)\@=',
      \ '}': '\>\%(\s*{\|\s*do\>\)\@!'}
function! s:highlight(group, ...) abort
  let value = rails#buffer().projected(a:0 ? a:1 : a:group)
  let words = split(join(filter(value, 'type(v:val) == type("")'), ' '))
  let special = filter(copy(words), 'type(v:val) == type("") && v:val =~# ''^\h\k*[][{}?!]$''')
  let regular = filter(copy(words), 'type(v:val) == type("") && v:val =~# ''^\h\k*$''')
  if !empty(special)
    exe 'syn match' a:group substitute(
          \ '"\<\%('.join(special, '\|').'\)"',
          \ '[][{}]', '\=get(s:special, submatch(0), submatch(0))', 'g')
  endif
  if !empty(regular)
    exe 'syn keyword' a:group join(regular, ' ')
  endif
endfunction

call s:highlight(
      \ rails#buffer().type_name('helper', 'view') ? 'rubyHelper' : 'rubyMacro',
      \ 'keywords')
call s:highlight('rubyMacro')
call s:highlight('rubyAction')
call s:highlight('rubyHelper')
call s:highlight('rubyEntity')
call s:highlight('rubyEntities')
