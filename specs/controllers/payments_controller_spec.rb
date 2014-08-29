require 'spec_helper'

describe PaymentsController do
  let(:user) { create(:user, student: create(:complete_student)) }
  before { sign_in(user) }

  describe "GET #index" do
    it "assigns the current user's charged payments" do
      users_payments = []
      uncharged_payments = []
      other_payment = create(:payment)
      3.times { users_payments << create(:payment, charged: true, user: user) }
      3.times { uncharged_payments << create(:payment, charged: false, user: user) }

      get :index
      payments = assigns(:payments)

      expect(payments).to include(*users_payments)
      expect(payments).to_not include(*other_payment)
      expect(payments).to_not include(*uncharged_payments)
    end

    it "renders the index" do
      get :index
      expect(response).to render_template(:index)
    end
  end

  describe "GET #new" do
    it "assigns the payment" do
      get :new
      expect(assigns(:payment)).to be
    end

    it "renders the new template" do
      get :new
      expect(response).to render_template(:new)
    end
  end

  describe "POST #create" do
    let(:payment_attrs) { attributes_for(:payment) }

    it "creates a payment" do
      post :create, payment: payment_attrs
      payment = assigns(:payment)
      expect(payment).to_not be_new_record
    end

    it "assigns the payment to the current_user" do
      post :create, payment: payment_attrs
      payment = assigns(:payment)
      expect(payment.user).to eql(user)
    end
  end

  describe "GET #show" do
    let(:payment) { create(:payment, user: user) }

    it "assigns the payment" do
      get :show, id: payment.id
      expect(assigns(:payment)).to eql(payment)
    end
  end

  describe "PATCH #update" do
    context "PayPal" do
      context "new payment" do
        before do
          stub_paypal_request
        end

        it "redirects to PayPal" do
          payment = create(:payment, user: user)
          patch :update, id: payment.id, payment: { payment_method: 'paypal' }
          paypal_uri = "https://www.sandbox.paypal.com/cgi-bin/webscr?cmd=_express-checkout&token="
          expect(response).to redirect_to(paypal_uri)
        end
      end

      context "successful and confirmed payment" do
        let(:payment) do
          create(:payment,
                 user: user,
                 paypal_token: "123abc",
                 paypal_payer_id: "456def",
                 payment_method: 'paypal')
        end

        before do
          controller.current_user.stub(payments: stub(find: payment))
          payment.stub(:charge)
        end

        it "assigns the payment" do
          patch :update, id: payment.id
          expect(assigns(:payment)).to eql(payment)
        end

        it "does charge" do
          payment.should_receive(:charge)
          patch :update, id: payment.id
        end

        it "redirects to billing tab" do
          patch :update, id: payment.id
          notice = I18n.t('payments.paypal.payment-succeeded.title')
          expect(flash[:notice]).to eql(notice)
          expect(response).to redirect_to(billing_account_url)
        end
      end
    end

    context "Stripe" do
      let(:payment) do
        create(:payment, user: user)
      end

      before do
        controller.current_user.stub(payments: stub(find: payment))
        payment.stub(charge: true)
      end

      it "assigns the payment" do
        patch :update, id: payment.id, stripeToken: "foobarbaz", payment: { payment_method: 'stripe' }
        expect(assigns(:payment)).to eql(payment)
      end

      it "does charge" do
        payment.should_receive(:charge)
        patch :update, id: payment.id, stripeToken: "foobarbaz", payment: { payment_method: 'stripe' }
      end

      it "redirects to billing tab" do
        patch :update, id: payment.id, stripeToken: "foobarbaz", payment: { payment_method: 'stripe' }
        notice = I18n.t('payments.stripe.payment-succeeded.title')
        expect(flash[:notice]).to eql(notice)
        expect(response).to redirect_to(billing_account_url)
      end
    end
  end

  describe "GET #paypal_success" do
    let(:payment) { create(:payment) }

    before do
      controller.current_user.stub(payments: stub(find: payment))
    end

    it "sets the token" do
      payment.should_receive(:paypal_token=).with("token")
      get :paypal_success, id: payment.id, token: "token", PayerID: "paypal_payer_id"
    end

    it "sets the payer id" do
      payment.should_receive(:paypal_payer_id=).with("paypal_payer_id")
      get :paypal_success, id: payment.id, token: "token", PayerID: "paypal_payer_id"
    end

     it "does not charge" do
       payment.should_not_receive(:charge)
       get :paypal_success, id: payment.id, token: "token", PayerID: "paypal_payer_id"
     end

     it "redirects to the new payment url" do
       get :paypal_success, id: payment.id, token: "token", PayerID: "paypal_payer_id"
       expect(response).to redirect_to(payment)
     end
  end

  describe "GET #paypal_cancel" do
    it "displays a payment failed notification" do
      get :paypal_cancel, id: "foo"
      alert = I18n.t('payments.paypal.payment-cancel')
      expect(flash[:alert]).to eql(alert)
      expect(response).to redirect_to(new_payment_url)
    end
  end

  describe "POST #alipay_notify" do
    let(:payment) { create(:payment, user: user, sessions_count: 4, currency: "CNY", payment_method: 'alipay') }
    before do
      Alipay::Notify.stub(verify?: true)
    end

    it "still returns a 200 when it's a bad notification" do
      params = {
        "action" => "alipay_notify",
        "controller" => "payments",
        "currency" => "USD",
        "id" => "13000176",
        "notify_id" => "348239c82394d2d77db64bd8e31f9d5b7e",
        "notify_time" => "2013-10-11 22:56:09",
        "notify_type" => "trade_status_sync",
        "out_trade_no" => "#{payment.id}",
        "sign" => "38cf412a991a65a8667034db696546b1",
        "sign_type" => "MD5",
        "total_fee" => "18.94",
        "trade_no" => "2013101136712297",
        "trade_status" => "TRADE_CLOSED"
      }
      post :alipay_notify, params
      expect(response.body).to eql("success")
      expect(response.status).to eql(200)
    end

    it "returns a 200" do
      params = {
        "action" => "alipay_notify",
        "controller" => "payments",
        "currency" => "USD",
        "id" => "13000176",
        "notify_id" => "348239c82394d2d77db64bd8e31f9d5b7e",
        "notify_time" => "2013-10-11 22:56:09",
        "notify_type" => "trade_status_sync",
        "out_trade_no" => "#{payment.id}",
        "sign" => "38cf412a991a65a8667034db696546b1",
        "sign_type" => "MD5",
        "total_fee" => "18.94",
        "trade_no" => "2013101136712297",
        "trade_status" => "TRADE_FINISHED"
      }
      post :alipay_notify, params
      expect(response.body).to eql("success")
      expect(response.status).to eql(200)
      expect(assigns(:payment)).to be_charged
      expect(assigns(:payment).user.sessions_count).to eql(5)
    end
  end
end
