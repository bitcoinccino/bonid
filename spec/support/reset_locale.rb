# frozen_string_literal: true

# Requests for citizens with a preferred language set I18n.locale for the
# rest of the process. Reset it after every example so one French/Kreyòl
# test can't change the language another test expects.
RSpec.configure do |config|
  config.after { I18n.locale = I18n.default_locale }
end
