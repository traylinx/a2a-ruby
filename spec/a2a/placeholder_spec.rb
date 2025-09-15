# frozen_string_literal: true

require "spec_helper"

RSpec.describe "A2A Placeholder" do
  it "has a version number" do
    expect(A2A::VERSION).not_to be_nil
  end

  it "can be configured" do
    expect(A2A.configuration).to be_a(A2A::Configuration)
  end
end
