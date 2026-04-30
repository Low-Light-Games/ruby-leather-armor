require 'rails_helper'

RSpec.describe 'Adventure Messages initiative-pending gate', type: :request do
  let(:user)      { create(:user, :password_auth) }
  let(:story)     { create(:story) }
  let(:adventure) { create(:adventure, user: user, story: story) }
  let!(:sheet)    { create(:adventure_sheet, adventure: adventure) }

  before { sign_in(user) }

  describe 'POST /adventures/:id/messages while an initiative request is pending' do
    before do
      adventure.adventure_messages.create!(
        role: 'dm',
        content: 'Roll for initiative!',
        message_type: 'initiative_request',
        metadata: { initiative_request: { 'creature_data' => [], 'intent' => { 'intention' => 'fight' } } }
      )
    end

    it 'returns 422 with initiative_pending instead of enqueuing the prompt' do
      expect(PipelineJob).not_to receive(:perform_later)

      post "/adventures/#{adventure.id}/messages",
           params: { content: 'Initiative: 25' },
           headers: { 'Accept' => 'application/json' }

      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body['error_code']).to eq('initiative_pending')
      expect(body['error']).to match(/initiative roll/i)
    end

    it 'still allows POST /messages/initiative to resume the pipeline' do
      expect(InitiativePipelineJob).to receive(:perform_later)

      post "/adventures/#{adventure.id}/messages/initiative",
           params: { initiative: 25 },
           headers: { 'Accept' => 'application/json' }

      expect(response).to have_http_status(:accepted)
    end
  end

  describe 'POST /adventures/:id/messages with no initiative pending' do
    it 'enqueues the prompt as usual' do
      expect(PipelineJob).to receive(:perform_later)

      post "/adventures/#{adventure.id}/messages",
           params: { content: 'I look around.' },
           headers: { 'Accept' => 'application/json' }

      expect(response).to have_http_status(:accepted)
    end
  end
end
