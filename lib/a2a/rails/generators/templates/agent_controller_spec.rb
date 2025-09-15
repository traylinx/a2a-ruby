# frozen_string_literal: true

require 'rails_helper'

RSpec.describe <%= controller_class_name %>, type: :controller do
  describe "A2A Agent functionality" do
    describe "GET #agent_card" do
      it "returns the agent card" do
        get :agent_card
        
        expect(response).to have_http_status(:ok)
        expect(response.content_type).to eq("application/json; charset=utf-8")
        
        card = JSON.parse(response.body)
        expect(card).to include(
          "name" => "<%= class_name.humanize %> Agent",
          "description" => "<%= agent_description %>",
          "version" => "1.0.0"
        )
      end
    end

    describe "POST #rpc" do
      let(:valid_rpc_request) do
        {
          jsonrpc: "2.0",
          method: "status",
          params: {},
          id: 1
        }
      end

      it "handles valid JSON-RPC requests" do
        post :rpc, body: valid_rpc_request.to_json, as: :json
        
        expect(response).to have_http_status(:ok)
        
        rpc_response = JSON.parse(response.body)
        expect(rpc_response).to include(
          "jsonrpc" => "2.0",
          "id" => 1
        )
        expect(rpc_response["result"]).to be_present
      end

      it "returns error for invalid JSON-RPC" do
        post :rpc, body: "invalid json", as: :json
        
        expect(response).to have_http_status(:bad_request)
        
        error_response = JSON.parse(response.body)
        expect(error_response["error"]).to be_present
      end

      <% if skills.any? %>
      <% skills.each do |skill| %>
      describe "<%= skill %> method" do
        let(:<%= skill %>_request) do
          {
            jsonrpc: "2.0",
            method: "<%= skill.underscore %>",
            params: { test: "data" },
            id: 1
          }
        end

        it "handles <%= skill %> requests" do
          post :rpc, body: <%= skill %>_request.to_json, as: :json
          
          expect(response).to have_http_status(:ok)
          
          rpc_response = JSON.parse(response.body)
          expect(rpc_response["result"]).to include("skill" => "<%= skill %>")
        end
      end
      <% end %>
      <% end %>

      describe "status method" do
        let(:status_request) do
          {
            jsonrpc: "2.0",
            method: "status",
            params: {},
            id: 1
          }
        end

        it "returns agent status information" do
          post :rpc, body: status_request.to_json, as: :json
          
          expect(response).to have_http_status(:ok)
          
          rpc_response = JSON.parse(response.body)
          status_result = rpc_response["result"]
          
          expect(status_result).to include(
            "agent" => "<%= class_name %>",
            "status" => "active",
            "version" => "1.0.0"
          )
        end
      end
    end

    <% if with_authentication? %>
    describe "authentication" do
      context "when authentication is required" do
        <% authentication_methods.each do |method| %>
        describe "<%= method %> method" do
          let(:auth_request) do
            {
              jsonrpc: "2.0",
              method: "<%= method %>",
              params: {},
              id: 1
            }
          end

          it "requires authentication" do
            post :rpc, body: auth_request.to_json, as: :json
            
            expect(response).to have_http_status(:unauthorized)
          end

          it "allows authenticated requests" do
            # Mock authentication - customize based on your auth system
            allow(controller).to receive(:current_user_authenticated?).and_return(true)
            allow(controller).to receive(:current_user_info).and_return({ id: 1, name: "Test User" })
            
            post :rpc, body: auth_request.to_json, as: :json
            
            expect(response).to have_http_status(:ok)
          end
        end
        <% end %>
      end
    end
    <% end %>
  end

  describe "A2A protocol compliance" do
    it "includes A2A::Rails::ControllerHelpers" do
      expect(controller.class.included_modules).to include(A2A::Rails::ControllerHelpers)
    end

    it "has A2A capabilities defined" do
      capabilities = controller.class._a2a_capabilities
      expect(capabilities).to be_present
      expect(capabilities).to be_an(Array)
    end

    it "has A2A methods defined" do
      methods = controller.class._a2a_methods
      expect(methods).to be_present
      expect(methods).to be_a(Hash)
      expect(methods).to include("status")
    end
  end
end