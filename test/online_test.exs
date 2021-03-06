
# Created by Patrick Schneider on 03.06.2017.
# Copyright (c) 2017 MeetNow! GmbH

defmodule OnlineTest do
  use ExUnit.Case, async: false
  use ExVCR.Mock, options: [clear_mock: true]

  setup_all do
    ExVCR.Config.cassette_library_dir("fixture/vcr_cassettes")
    :ok
  end

  test "server requests" do
    s = ICouch.server_connection("http://192.168.99.100:8000/")

    use_cassette "server_requests", match_requests_on: [:query] do
      :ibrowse.start()

      # Get server info
      assert ICouch.server_info(s) === {:ok, %{"couchdb" => "Welcome",
        "uuid" => "280e57631ecac1682459dda6f750186c", "vendor" => %{
          "name" => "The Apache Software Foundation", "version" => "1.6.1"},
        "version" => "1.6.1"}}

      # Get all databases
      assert ICouch.all_dbs(s) === {:ok, ["_replicator", "_users", "test_db"]}

      # Get a single uuid
      assert ICouch.get_uuid!(s) === "11d44b0640a7cc8a645610ea57002278"

      # Get a number of uuids
      assert ICouch.get_uuids!(s, 3) === ["11d44b0640a7cc8a645610ea570031f5",
        "11d44b0640a7cc8a645610ea57003eb7", "11d44b0640a7cc8a645610ea5700408c"]
    end
  end

  test "database management" do
    s = ICouch.server_connection("http://192.168.99.100:8000/")
    sa = ICouch.server_connection("http://admin:admin@192.168.99.100:8000/")

    use_cassette "database_management" do
      :ibrowse.start()

      # Try to open a non-existent database
      assert_raise ICouch.RequestError, "Not Found", fn -> ICouch.open_db!(s, "nonexistent") end

      # Try to create a database without authorization
      assert_raise ICouch.RequestError, "Unauthorized", fn -> ICouch.assert_db!(s, "fail_new") end

      # Create a database
      d = ICouch.assert_db!(sa, "test_new")
      assert d === %ICouch.DB{name: "test_new", server: sa}

      # Get database info
      assert ICouch.db_info(d) === {:ok, %{"committed_update_seq" => 0,
        "compact_running" => false, "data_size" => 0, "db_name" => "test_new",
        "disk_format_version" => 6, "disk_size" => 79, "doc_count" => 0,
        "doc_del_count" => 0, "instance_start_time" => "1504260367442461",
        "purge_seq" => 0, "update_seq" => 0}}

      # Delete a database
      assert ICouch.delete_db(d) === :ok

      # Try to delete a non-existent database
      assert ICouch.delete_db(sa, "nonexistent") === {:error, :not_found}

      # Try to create an existing database
      assert_raise ICouch.RequestError, "Precondition Failed", fn -> ICouch.create_db!(sa, "test_db") end
    end
  end

  test "document handling" do
    s = ICouch.server_connection("http://192.168.99.100:8000/")

    att_doc = %ICouch.Document{attachment_data: %{},
      attachment_order: ["small-jpeg.jpg"], fields: %{
        "_attachments" => %{"small-jpeg.jpg" => %{
          "content_type" => "image/jpeg",
          "digest" => "md5-VY+mp2HtUEbf51mWfJQi0g==", "length" => 125,
          "revpos" => 2, "stub" => true}},
        "_id" => "att_doc", "_rev" => "2-1c506497a595685a2bb932820aa64e2a",
        "key" => "le_key", "value" => "la_value"},
      id: "att_doc", rev: "2-1c506497a595685a2bb932820aa64e2a"}

    att_data = Base.decode64!("/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAAMCAgICAgMCAgIDAwMDBAYEBAQEBAgGBgUGCQgKCgkICQkKDA8MCgsOCwkJDRENDg8QEBEQCgwSExIQEw8QEBD/yQALCAABAAEBAREA/8wABgAQEAX/2gAIAQEAAD8A0s8g/9k=")

    att_doc_whad = ICouch.Document.put_attachment_data(att_doc, "small-jpeg.jpg", att_data)

    new_doc = %ICouch.Document{attachment_data: %{
        "test" => "This is a very simple text file."},
      attachment_order: ["test"], fields: %{"_attachments" => %{
          "test" => %{"content_type" => "application/octet-stream", "length" => 32,
            "stub" => true}},
        "_id" => "new_doc", "key" => "the_key", "value" => "the_value"},
      id: "new_doc", rev: nil}

    saved_doc = ICouch.Document.set_rev(new_doc, "1-12c0ccf8993ea47d1a7893cb0b8dae3e")

    saved_doc_whai = ICouch.Document.put_attachment_info(saved_doc, "test", %{
      "content_type" => "application/octet-stream", "length" => 32, "stub" => true,
      "digest" => "md5-xhhZ0oUF8fnIYvXlVxS1PQ==", "revpos" => 1})

    use_cassette "document_handling", match_requests_on: [:query, :headers] do
      :ibrowse.start()
      d = ICouch.open_db!(s, "test_db")

      # Test for non-existent document
      assert ICouch.doc_exists?(d, "nonexistent") === false
      assert ICouch.get_doc_rev(d, "nonexistent") === {:error, :not_found}
      assert_raise ICouch.RequestError, "Not Found", fn -> ICouch.open_doc!(d, "nonexistent") end

      # Test for existing document
      assert ICouch.doc_exists?(d, "att_doc") === true
      assert ICouch.get_doc_rev(d, "att_doc") === {:ok, "2-1c506497a595685a2bb932820aa64e2a"}

      # Open document
      assert ICouch.open_doc!(d, "att_doc") === att_doc

      # Open document with attachments (using Base64)
      assert ICouch.open_doc!(d, "att_doc", attachments: true, multipart: false) === att_doc_whad

      # Create document
      assert ICouch.save_doc!(d, new_doc, multipart: "UnitTestBoundary") === saved_doc

      # Re-open document (using Multipart)
      assert ICouch.open_doc!(d, "new_doc", attachments: true) === saved_doc_whai

      # Duplicate document
      assert {:ok, dup_response} = ICouch.dup_doc(d, saved_doc)

      # Delete documents
      assert {:ok, %{"id" => "new_doc", "ok" => true}} = ICouch.delete_doc(d, saved_doc)
      assert {:ok, %{"ok" => true}} = ICouch.delete_doc(d, dup_response["id"], rev: dup_response["rev"])
    end
  end
end
