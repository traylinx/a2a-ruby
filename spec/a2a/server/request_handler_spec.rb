# frozen_string_literal: true

require "spec_helper"

RSpec.describe A2A::Server::RequestHandler do
  let(:handler) { described_class.new }

  describe "abstract methods" do
    it "raises NotImplementedError for on_get_task" do
      expect { handler.on_get_task({}) }.to raise_error(NotImplementedError)
    end

    it "raises NotImplementedError for on_cancel_task" do
      expect { handler.on_cancel_task({}) }.to raise_error(NotImplementedError)
    end

    it "raises NotImplementedError for on_message_send" do
      expect { handler.on_message_send({}) }.to raise_error(NotImplementedError)
    end

    it "raises UnsupportedOperation for on_message_send_stream" do
      expect { handler.on_message_send_stream({}) }.to raise_error(A2A::Errors::UnsupportedOperation)
    end

    it "raises NotImplementedError for push notification methods" do
      expect { handler.on_set_task_push_notification_config({}) }.to raise_error(NotImplementedError)
      expect { handler.on_get_task_push_notification_config({}) }.to raise_error(NotImplementedError)
      expect { handler.on_list_task_push_notification_config({}) }.to raise_error(NotImplementedError)
      expect { handler.on_delete_task_push_notification_config({}) }.to raise_error(NotImplementedError)
    end

    it "raises UnsupportedOperation for on_resubscribe_to_task" do
      expect { handler.on_resubscribe_to_task({}) }.to raise_error(A2A::Errors::UnsupportedOperation)
    end
  end
end