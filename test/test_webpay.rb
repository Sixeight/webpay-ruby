# -*- coding: utf-8 -*-
require File.expand_path('../test_helper', __FILE__)
require 'test/unit'
require 'shoulda'
require 'mocha'
require 'pp'
require 'rest-client'
require 'cgi'
require 'uri'

class TestWebpayRuby < Test::Unit::TestCase
  include Mocha

  context "Util" do
    should "symbolize_names should convert names to symbols" do
      start = {
        'foo' => 'bar',
        'array' => [{ 'foo' => 'bar' }],
        'nested' => {
          1 => 2,
          :symbol => 9,
          'string' => nil
        }
      }
      finish = {
        :foo => 'bar',
        :array => [{ :foo => 'bar' }],
        :nested => {
          1 => 2,
          :symbol => 9,
          :string => nil
        }
      }

      symbolized = Webpay::Util.symbolize_names(start)
      assert_equal(finish, symbolized)
    end
  end

  context "API Bindings" do
    setup do
      @mock = mock
      Webpay.mock_rest_client = @mock
    end

    teardown do
      Webpay.mock_rest_client = nil
    end

    should "creating a new APIResource should not fetch over the network" do
      @mock.expects(:get).never
      c = Webpay::Customer.new("someid")
    end

    should "creating a new APIResource from a hash should not fetch over the network" do
      @mock.expects(:get).never
      c = Webpay::Customer.construct_from({
        :id => "somecustomer",
        :card => {:id => "somecard", :object => "card"},
        :object => "customer"
      })
    end

    should "setting an attribute should not cause a network request" do
      @mock.expects(:get).never
      @mock.expects(:post).never
      c = Webpay::Customer.new("test_customer");
      c.card = {:id => "somecard", :object => "card"}
    end

    should "accessing id should not issue a fetch" do
      @mock.expects(:get).never
      c = Webpay::Customer.new("test_customer");
      c.id
    end

    should "not specifying api credentials should raise an exception" do
      Webpay.api_key = nil
      assert_raises Webpay::AuthenticationError do
        Webpay::Customer.new("test_customer").refresh
      end
    end

    should "specifying invalid api credentials should raise an exception" do
      Webpay.api_key = "invalid"
      response = test_response(test_invalid_api_key_error, 401)
      assert_raises Webpay::AuthenticationError do
        @mock.expects(:get).once.raises(RestClient::ExceptionWithResponse.new(response, 401))
        Webpay::Customer.retrieve("failing_customer")
      end
    end

    should "AuthenticationErrors should have an http status, http body, and JSON body" do
      Webpay.api_key = "invalid"
      response = test_response(test_invalid_api_key_error, 401)
      begin
        @mock.expects(:get).once.raises(RestClient::ExceptionWithResponse.new(response, 401))
        Webpay::Customer.retrieve("failing_customer")
      rescue Webpay::AuthenticationError => e
        assert_equal(401, e.http_status)
        assert_equal(true, !!e.http_body)
        assert_equal(true, !!e.json_body[:error][:message])
        assert_equal(test_invalid_api_key_error['error']['message'], e.json_body[:error][:message])
      end
    end

    context "with valid credentials" do
      setup do
        Webpay.api_key="foo"
      end

      teardown do
        Webpay.api_key=nil
      end

      should "a 400 should give an InvalidRequestError with http status, body, and JSON body" do
        response = test_response(test_missing_id_error, 400)
        @mock.expects(:get).once.raises(RestClient::ExceptionWithResponse.new(response, 404))
        begin
          Webpay::Customer.retrieve("foo")
        rescue Webpay::InvalidRequestError => e
          assert_equal(400, e.http_status)
          assert_equal(true, !!e.http_body)
          assert_equal(true, e.json_body.kind_of?(Hash))
        end
      end

      should "a 401 should give an AuthenticationError with http status, body, and JSON body" do
        response = test_response(test_missing_id_error, 401)
        @mock.expects(:get).once.raises(RestClient::ExceptionWithResponse.new(response, 404))
        begin
          Webpay::Customer.retrieve("foo")
        rescue Webpay::AuthenticationError => e
          assert_equal(401, e.http_status)
          assert_equal(true, !!e.http_body)
          assert_equal(true, e.json_body.kind_of?(Hash))
        end
      end

      should "a 402 should give a CardError with http status, body, and JSON body" do
        response = test_response(test_missing_id_error, 402)
        @mock.expects(:get).once.raises(RestClient::ExceptionWithResponse.new(response, 404))
        begin
          Webpay::Customer.retrieve("foo")
        rescue Webpay::CardError => e
          assert_equal(402, e.http_status)
          assert_equal(true, !!e.http_body)
          assert_equal(true, e.json_body.kind_of?(Hash))
        end
      end

      should "a 404 should give an InvalidRequestError with http status, body, and JSON body" do
        response = test_response(test_missing_id_error, 404)
        @mock.expects(:get).once.raises(RestClient::ExceptionWithResponse.new(response, 404))
        begin
          Webpay::Customer.retrieve("foo")
        rescue Webpay::InvalidRequestError => e
          assert_equal(404, e.http_status)
          assert_equal(true, !!e.http_body)
          assert_equal(true, e.json_body.kind_of?(Hash))
        end
      end

      should "setting a nil value for a param should exclude that param from the request" do
        @mock.expects(:get).with do |url, api_key, params|
          uri = URI(url)
          query = CGI.parse(uri.query)
          (url =~ %r{^https://api.webpay.jp/v1/charges?} &&
           query.keys.sort == ['offset', 'sad'])
        end.returns(test_response({ :count => 1, :data => [test_charge] }))
        c = Webpay::Charge.all(:count => nil, :offset => 5, :sad => false)

        @mock.expects(:post).with('https://api.webpay.jp/v1/charges', nil, { :amount => 50, :currency => 'usd', :card => {} }).returns(test_response({ :count => 1, :data => [test_charge] }))
        c = Webpay::Charge.create(:amount => 50, :currency => 'usd', :card => { :number => nil })
      end

      should "requesting with a unicode ID should result in a request" do
        response = test_response(test_missing_id_error, 404)
        @mock.expects(:get).once.with("https://api.webpay.jp/v1/customers/%E2%98%83", nil, nil).raises(RestClient::ExceptionWithResponse.new(response, 404))
        c = Webpay::Customer.new("☃")
        assert_raises(Webpay::InvalidRequestError) { c.refresh }
      end

      should "requesting with no ID should result in an InvalidRequestError with no request" do
        c = Webpay::Customer.new
        assert_raises(Webpay::InvalidRequestError) { c.refresh }
      end

      should "making a GET request with parameters should have a query string and no body" do
        params = { :limit => 1 }
        @mock.expects(:get).once.with("https://api.webpay.jp/v1/charges?limit=1", nil, nil).returns(test_response([test_charge]))
        c = Webpay::Charge.all(params)
      end

      should "making a POST request with parameters should have a body and no query string" do
        params = { :amount => 100, :currency => 'usd', :card => 'sc_token' }
        @mock.expects(:post).once.with { |url, get, post| get.nil? and post == params }.returns(test_response(test_charge))
        c = Webpay::Charge.create(params)
      end

      should "loading an object should issue a GET request" do
        @mock.expects(:get).once.returns(test_response(test_customer))
        c = Webpay::Customer.new("test_customer")
        c.refresh
      end

      should "using array accessors should be the same as the method interface" do
        @mock.expects(:get).once.returns(test_response(test_customer))
        c = Webpay::Customer.new("test_customer")
        c.refresh
        assert_equal c.created, c[:created]
        assert_equal c.created, c['created']
        c['created'] = 12345
        assert_equal c.created, 12345
      end

      should "accessing a property other than id or parent on an unfetched object should fetch it" do
        @mock.expects(:get).once.returns(test_response(test_customer))
        c = Webpay::Customer.new("test_customer")
        c.charges
      end

      should "updating an object should issue a POST request with only the changed properties" do
        @mock.expects(:post).with("https://api.webpay.jp/v1/customers/c_test_customer", nil, {:mnemonic => 'another_mn'}).once.returns(test_response(test_customer))
        c = Webpay::Customer.construct_from(test_customer)
        c.mnemonic = "another_mn"
        c.save
      end

      should "updating should merge in returned properties" do
        @mock.expects(:post).once.returns(test_response(test_customer))
        c = Webpay::Customer.new("c_test_customer")
        c.mnemonic = "another_mn"
        c.save
        assert_equal false, c.livemode
      end

      should "deleting should send no props and result in an object that has no props other deleted" do
        @mock.expects(:get).never
        @mock.expects(:post).never
        @mock.expects(:delete).with("https://api.webpay.jp/v1/customers/c_test_customer", nil, nil).once.returns(test_response({ "id" => "test_customer", "deleted" => true }))

        c = Webpay::Customer.construct_from(test_customer)
        c.delete
        assert_equal true, c.deleted

        assert_raises NoMethodError do
          c.livemode
        end
      end

      should "loading an object with properties that have specific types should instantiate those classes" do
        @mock.expects(:get).once.returns(test_response(test_charge))
        c = Webpay::Charge.retrieve("test_charge")
        assert c.card.kind_of?(Webpay::WebpayObject) && c.card.object == 'card'
      end

      should "loading all of an APIResource should return an array of recursively instantiated objects" do
        @mock.expects(:get).once.returns(test_response(test_charge_array))
        c = Webpay::Charge.all.data
        assert c.kind_of? Array
        assert c[0].kind_of? Webpay::Charge
        assert c[0].card.kind_of?(Webpay::WebpayObject) && c[0].card.object == 'card'
      end

      context "account tests" do
        should "account should be retrievable" do
          resp = {:email => "test+bindings@webpay.jp", :charge_enabled => false, :details_submitted => false}
          @mock.expects(:get).once.returns(test_response(resp))
          a = Webpay::Account.retrieve
          assert_equal "test+bindings@webpay.jp", a.email
          assert !a.charge_enabled
          assert !a.details_submitted
        end
      end

      context "charge tests" do

        should "charges should be listable" do
          @mock.expects(:get).once.returns(test_response(test_charge_array))
          c = Webpay::Charge.all.data
          assert c.kind_of? Array
        end

        should "charges should be refundable" do
          @mock.expects(:get).never
          @mock.expects(:post).once.returns(test_response({:id => "ch_test_charge", :refunded => true}))
          c = Webpay::Charge.new("test_charge")
          c.refund
          assert c.refunded
        end

        should "charges should not be deletable" do
          assert_raises NoMethodError do
            @mock.expects(:get).once.returns(test_response(test_charge))
            c = Webpay::Charge.retrieve("test_charge")
            c.delete
          end
        end

        should "charges should be updateable" do
          @mock.expects(:get).once.returns(test_response(test_charge))
          @mock.expects(:post).once.returns(test_response(test_charge))
          c = Webpay::Charge.new("test_charge")
          c.refresh
          c.mnemonic = "New charge description"
          c.save
        end

        should "charges should have Card objects associated with their Card property" do
          @mock.expects(:get).once.returns(test_response(test_charge))
          c = Webpay::Charge.retrieve("test_charge")
          assert c.card.kind_of?(Webpay::WebpayObject) && c.card.object == 'card'
        end

        should "execute should return a new, fully executed charge when passed correct parameters" do
          @mock.expects(:post).with('https://api.webpay.jp/v1/charges', nil, {
            :currency => 'usd', :amount => 100,
            :card => {:exp_year => 2012, :number => '4242424242424242', :exp_month => 11}
          }).once.returns(test_response(test_charge))

          c = Webpay::Charge.create({
            :amount => 100,
            :card => {
              :number => "4242424242424242",
              :exp_month => 11,
              :exp_year => 2012,
            },
            :currency => "usd"
          })
          assert c.paid
        end

      end

      context "customer tests" do

        should "customers should be listable" do
          @mock.expects(:get).once.returns(test_response(test_customer_array))
          c = Webpay::Customer.all.data
          assert c.kind_of? Array
          assert c[0].kind_of? Webpay::Customer
        end

        should "customers should be deletable" do
          @mock.expects(:delete).once.returns(test_response(test_customer({:deleted => true})))
          c = Webpay::Customer.new("test_customer")
          c.delete
          assert c.deleted
        end

        should "customers should be updateable" do
          @mock.expects(:get).once.returns(test_response(test_customer({:mnemonic => "foo"})))
          @mock.expects(:post).once.returns(test_response(test_customer({:mnemonic => "bar"})))
          c = Webpay::Customer.new("test_customer").refresh
          assert_equal c.mnemonic, "foo"
          c.mnemonic = "bar"
          c.save
          assert_equal c.mnemonic, "bar"
        end

        should "customers should have Card objects associated with their active_ard property" do
          @mock.expects(:get).once.returns(test_response(test_customer))
          c = Webpay::Customer.retrieve("test_customer")
          assert c.active_card.kind_of?(Webpay::WebpayObject) && c.active_card.object == 'card'
        end

        should "create should return a new customer" do
          @mock.expects(:post).once.returns(test_response(test_customer))
          c = Webpay::Customer.create
          assert_equal "c_test_customer", c.id
        end

        should "be able to update a customer's subscription" do
          @mock.expects(:get).once.returns(test_response(test_customer))
          c = Webpay::Customer.retrieve("test_customer")

          @mock.expects(:post).once.with("https://api.webpay.jp/v1/customers/c_test_customer/subscription", nil, {:plan => 'silver'}).returns(test_response(test_subscription('silver')))
          s = c.update_subscription({:plan => 'silver'})

          assert_equal 'subscription', s.object
          assert_equal 'silver', s.plan.identifier
        end

        should "be able to cancel a customer's subscription" do
          @mock.expects(:get).once.returns(test_response(test_customer))
          c = Webpay::Customer.retrieve("test_customer")

          # Not an accurate response, but whatever
          
          @mock.expects(:delete).once.with("https://api.webpay.jp/v1/customers/c_test_customer/subscription?at_period_end=true", nil, nil).returns(test_response(test_subscription('silver')))
          s = c.cancel_subscription({:at_period_end => 'true'})

          @mock.expects(:delete).once.with("https://api.webpay.jp/v1/customers/c_test_customer/subscription?", nil, nil).returns(test_response(test_subscription('silver')))
          s = c.cancel_subscription
        end

        should "be able to delete a customer's discount" do
          @mock.expects(:get).once.returns(test_response(test_customer))
          c = Webpay::Customer.retrieve("test_customer")

          @mock.expects(:delete).once.with("https://api.webpay.jp/v1/customers/c_test_customer/discount", nil, nil).returns(test_response(test_delete_discount_response))
          s = c.delete_discount
          assert_equal nil, c.discount
        end
      end

      context "card tests" do
      end

      context "coupon tests" do
        should "create should return a new coupon" do
          @mock.expects(:post).once.returns(test_response(test_coupon))
          c = Webpay::Coupon.create
          assert_equal "co_test_coupon", c.id
        end
      end
      context "error checking" do

        should "404s should raise an InvalidRequestError" do
          response = test_response(test_missing_id_error, 404)
          @mock.expects(:get).once.raises(RestClient::ExceptionWithResponse.new(response, 404))

          begin
            Webpay::Customer.new("test_customer").refresh
            assert false #shouldn't get here either
          rescue Webpay::InvalidRequestError => e # we don't use assert_raises because we want to examine e
            assert e.kind_of? Webpay::InvalidRequestError
            assert_equal "id", e.param
            assert_equal "Missing id", e.message
            return
          end

          assert false #shouldn't get here
        end

        should "5XXs should raise an APIError" do
          response = test_response(test_api_error, 500)
          @mock.expects(:get).once.raises(RestClient::ExceptionWithResponse.new(response, 500))

          begin
            Webpay::Customer.new("test_customer").refresh
            assert false #shouldn't get here either
          rescue Webpay::APIError => e # we don't use assert_raises because we want to examine e
            assert e.kind_of? Webpay::APIError
            return
          end

          assert false #shouldn't get here
        end

        should "402s should raise a CardError" do
          response = test_response(test_invalid_exp_year_error, 402)
          @mock.expects(:get).once.raises(RestClient::ExceptionWithResponse.new(response, 402))

          begin
            Webpay::Customer.new("test_customer").refresh
            assert false #shouldn't get here either
          rescue Webpay::CardError => e # we don't use assert_raises because we want to examine e
            assert e.kind_of? Webpay::CardError
            assert_equal "invalid_expiry_year", e.code
            assert_equal "exp_year", e.param
            assert_equal "Your card's expiration year is invalid", e.message
            return
          end

          assert false #shouldn't get here
        end
      end
    end
  end
end
