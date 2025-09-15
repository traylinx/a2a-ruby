# frozen_string_literal: true

RSpec.describe A2A do
  it "has a version number" do
    expect(A2A::VERSION).not_to be_nil
  end

  describe ".configure" do
    it "yields configuration" do
      expect { |b| described_class.configure(&b) }.to yield_with_args(A2A::Configuration)
    end

    it "sets configuration" do
      described_class.configure do |config|
        config.default_timeout = 60
      end

      expect(described_class.config.default_timeout).to eq(60)
    end
  end

  describe ".config" do
    it "returns configuration instance" do
      expect(described_class.config).to be_a(A2A::Configuration)
    end
  end

  describe ".reset_configuration!" do
    it "resets configuration to defaults" do
      described_class.configure { |config| config.default_timeout = 60 }
      described_class.reset_configuration!

      expect(described_class.config.default_timeout).to eq(30)
    end
  end
end
