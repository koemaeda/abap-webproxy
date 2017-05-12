class ZWEBPROXY_REQUEST definition
  public
  create public .

public section.

  data HTTP_REQUEST type ref to IF_HTTP_REQUEST .
  data HTTP_RESPONSE type ref to IF_HTTP_RESPONSE .
  constants LIB_VERSION type STRING value '1.0.0' ##NO_TEXT.
  data RESPONSE_CODE type I .
  data RESPONSE_MESSAGE type STRING .
  data RESPONSE_HEADERS type TIHTTPNVP .
  data RESPONSE_DATA type XSTRING .

  methods CONSTRUCTOR
    importing
      value(METHOD) type STRING
      value(URI) type STRING
      value(HEADERS) type TIHTTPNVP
      value(POST_DATA) type XSTRING optional
      value(HTTP_VERSION_MAJOR) type I default 1
      value(HTTP_VERSION_MINOR) type I default 1
      value(PROXY_HOST) type STRING optional
      value(PROXY_PORT) type I optional
      value(PROXY_USERNAME) type STRING optional
      value(PROXY_PASSWORD) type STRING optional .
  methods RUN
    returning
      value(SUBRC) type SYSUBRC .
  methods GET_RAW_RESPONSE
    returning
      value(RESPONSE) type STRING .
protected section.

  data REQUEST_HEADERS type TIHTTPNVP .
  data METHOD type STRING .
  data URI type STRING .
  data HTTP_VERSION_MAJOR type N .
  data HTTP_VERSION_MINOR type N .
  data POST_DATA type XSTRING .
  data HTTP_CLIENT type ref to IF_HTTP_CLIENT .
  data SYSTEM_INFO type RFCSI .
  data CLIENT_IP type STRING .

  methods GET_STACK_TRACE
    returning
      value(STACK_TRACE) type STRING .
  methods BUILD_ERROR_RESPONSE
    importing
      !HEADER type STRING
      !MESSAGE type STRING default 'Unexpected error' .
private section.
ENDCLASS.



CLASS ZWEBPROXY_REQUEST IMPLEMENTATION.


  method build_error_response.
    find regex '(\d+) (.+)' in header submatches data(lv_code) me->response_message.
    me->response_code = lv_code.

    append value #( name = 'Content-Type' value = 'text/html;charset=utf-8' ) to me->response_headers.

    data(lv_str_data) =
      |<h1>{ header }</h1>\r\n| &&
      |<hr>\r\n| &&
      |<p>{ message }</p>\r\n| &&
      |<b>Stack trace</b>:<br>\r\n| &&
      |<pre>{ get_stack_trace( ) }</pre>\r\n| &&
      |<hr>\r\n| &&
      |<small>{ sy-sysid } { sy-mandt } - { system_info-rfchost } ({ system_info-rfcipaddr }) - | &&
      |{ system_info-rfcsaprl }/{ system_info-rfcopsys }<br>\r\n| &&
      |<a href="https://github.com/koemaeda/abap-webproxy">ABAP Web Proxy { me->lib_version }</a></small>\r\n|.

    data(lo_conv) = cl_abap_conv_out_ce=>create( encoding = 'UTF-8' ).
    lo_conv->convert( exporting data = lv_str_data importing buffer = me->response_data ).
  endmethod.


  method constructor.
    "// Read client/server information
    data: lv_terminal type usr41-terminal.
    call function 'TERMINAL_ID_GET'
      importing
        terminal = lv_terminal
      exceptions
        others   = 4.
    if sy-subrc = 0.
      find regex '([\d\.]+)' in lv_terminal submatches me->client_ip.
    endif.
    call function 'RFC_SYSTEM_INFO'
      importing
        rfcsi_export = me->system_info.

    "// Request parameter checks
    if method is initial or uri is initial.
      build_error_response( header = '400 Bad Request' message = 'Empty request' ).
      return.
    endif.

    me->method = method.
    me->uri = uri.
    me->request_headers = headers.
    me->post_data = post_data.
    me->http_version_major = http_version_major.
    me->http_version_minor = http_version_minor.

    "// Setup the HTTP client
    cl_http_client=>create_by_url(
      exporting
        url = me->uri
        proxy_host    = proxy_host
        proxy_service = conv string( proxy_port )
      importing client = me->http_client
      exceptions others = 8
    ).
    if sy-subrc <> 0.
      build_error_response( header = '400 Bad Request'
        message = 'Could not create CL_HTTP_CLIENT instance' ).
      return.
    endif.

    "// Proxy authentication
    if proxy_username is not initial.
      me->http_client->authenticate(
        proxy_authentication = 'X'
        username = proxy_username
        password = proxy_password
      ).
    endif.

    me->http_request = me->http_client->request.

    "// Build raw request (for consistency)
    data(lo_sb) = new cl_abap_string_c_writer( ).
    lo_sb->write(
      |{ me->method } { me->uri } HTTP/{ me->http_version_major }.{ me->http_version_minor }\r\n| ).
    loop at me->request_headers assigning field-symbol(<header>).
      lo_sb->write( |{ <header>-name }: { <header>-value }\r\n| ).
    endloop.
    lo_sb->write( |X-Forwarded-For: { me->client_ip }\r\n| ).
    lo_sb->write( |\r\n| ).

    data(lo_xb) = new cl_abap_string_x_writer( ).
    lo_xb->write( cl_http_utility=>encode_utf8( lo_sb->get_result_string( ) ) ).
    lo_xb->write( me->post_data ).
    me->http_request->from_xstring( lo_xb->get_result_string( ) ).
  endmethod.


  method GET_RAW_RESPONSE.
    data(lo_conv) = cl_abap_conv_in_ce=>create( encoding = 'UTF-8' ).
    lo_conv->convert( exporting input = me->http_response->to_xstring( ) importing data = response ).
  endmethod.


  method get_stack_trace.
    data: lt_callstack type abap_callstack.
    call function 'SYSTEM_CALLSTACK'
      importing
        callstack = lt_callstack.
    delete lt_callstack index 1. "// Ignore oneself

    data(lo_sb) = new cl_abap_string_c_writer( ).
    loop at lt_callstack assigning field-symbol(<line>).
      lo_sb->write( |{ sy-tabix } -> { <line>-blocktype } { <line>-blockname } - | &&
        |({ <line>-mainprogram }) { <line>-include }:{ <line>-line }\r\n| ).
    endloop.

    stack_trace = lo_sb->get_result_string( ).
  endmethod.


  method run.
    data: lv_http_error type string.

    "// Check if the HTTP client is valid
    if me->http_client is initial or me->http_request is initial.
      if me->response_code is initial.
        build_error_response( '500 Internal Server Error' ).
      endif.
      subrc = 8.
      return.
    endif.

    "// Check request method
    case me->method.
      when 'GET' or 'POST' or 'HEAD' or 'PUT' or 'DELETE'.
      when others.
        build_error_response( header = '405 Method Not Allowed'
          message = |Method { me->method } is not supported| ).
        subrc = 8.
        return.
    endcase.

    "// Go!
    me->http_client->send(
      exceptions
        http_communication_failure = 1
        http_invalid_state = 2
        http_processing_failed = 3
        http_invalid_timeout = 4
      ).
    if sy-subrc <> 0.
      me->http_client->get_last_error( importing code = subrc message = lv_http_error ).
      build_error_response( header = '500 Internal Server Error'
        message = |CL_HTTP_CLIENT->SEND failed: { subrc } - { lv_http_error }| ).
      return.
    endif.

    me->http_client->receive(
      exceptions
        http_communication_failure = 1
        http_invalid_state = 2
        http_processing_failed = 3
      ).
    if sy-subrc <> 0.
      me->http_client->get_last_error( importing code = subrc message = lv_http_error ).
      build_error_response( header = '500 Internal Server Error'
        message = |CL_HTTP_CLIENT->RECEIVE failed: { subrc } - { lv_http_error }| ).
      return.
    endif.

    data(lv_teste) = cl_http_utility=>decode_utf8( me->http_request->to_xstring( ) ).

    me->http_response = me->http_client->response.
    me->http_response->get_status( importing
      code = me->response_code reason = me->response_message ).
    me->response_data = me->http_response->get_data( ).

    "// One last error check, just in case
    me->http_client->get_last_error( importing code = subrc message = lv_http_error ).
    if subrc <> 0 and me->response_code is initial.
      build_error_response( |CL_HTTP_CLIENT failed: { subrc } - { lv_http_error }| ).
    endif.

    "// Parse returned HTTP headers
    "// (standard CL_HTTP_CLIENT does a bad job at this)
    data: lv_raw_response type string.
    data(lo_conv) = cl_abap_conv_in_ce=>create( encoding = 'UTF-8' ignore_cerr = 'X' ).
    lo_conv->convert( exporting input = me->http_response->get_raw_message( )
      importing data = lv_raw_response ).
    split lv_raw_response at |\r\n\r\n| into data(lv_raw_headers) data(lv_body).
    split lv_raw_headers at |\r\n| into table data(lt_raw_headers).
    delete lt_raw_headers index 1.
    loop at lt_raw_headers assigning field-symbol(<raw_header>).
      split <raw_header> at ':' into data(lv_name) data(lv_value).
      condense: lv_name, lv_value.
      append value #( name = lv_name value = lv_value ) to me->response_headers.
    endloop.
  endmethod.
ENDCLASS.
