require 'test_helper'

class Capistrano::StretcherTest < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::Capistrano::Stretcher::VERSION
  end
end
