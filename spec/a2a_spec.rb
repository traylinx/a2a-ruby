# frozen_string_literal: true

RSpec.describe A2A do
  it "has a version number" do
    expect(A2A::VERSION).not_to be nil
  end

  describe ".configure" do
    it "yields configuration" do
      expect { |b| A2A.configure(&b) }.to yield_with_args(A2A::Configuration)
    end

    it "sets configuration" do
      A2A.configure do |config|
        config.default_timeout = 60
      end

      expect(A2A.config.default_timeout).to eq(60)
    end
  end

  describe ".config" do
    it "returns configuration instance" do
      expect(A2A.config).to be_a(A2A::Configuration)
    end
  end

  describe ".reset_configuration!" do
    it "resets configuration to defaults" do
      A2A.configure { |config| config.default_timeout = 60 }
      A2A.reset_configuration!
      
      expect(A2A.config.default_timeout).to eq(30)
    end
  end
end