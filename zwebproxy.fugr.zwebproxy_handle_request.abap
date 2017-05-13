function zwebproxy_handle_request.
*"----------------------------------------------------------------------
*"*"Interface local:
*"  IMPORTING
*"     VALUE(METHOD) TYPE  STRING
*"     VALUE(URI) TYPE  STRING
*"     VALUE(REQUEST_HEADERS) TYPE  TIHTTPNVP OPTIONAL
*"     VALUE(POST_DATA_B64) TYPE  STRING OPTIONAL
*"     VALUE(HTTP_VERSION_MAJOR) TYPE  I DEFAULT 1
*"     VALUE(HTTP_VERSION_MINOR) TYPE  I DEFAULT 1
*"     VALUE(PROXY_HOST) TYPE  STRING OPTIONAL
*"     VALUE(PROXY_PORT) TYPE  I OPTIONAL
*"     VALUE(PROXY_USERNAME) TYPE  STRING OPTIONAL
*"     VALUE(PROXY_PASSWORD) TYPE  STRING OPTIONAL
*"  EXPORTING
*"     VALUE(SUBRC) TYPE  SYSUBRC
*"     VALUE(CODE) TYPE  I
*"     VALUE(MESSAGE) TYPE  STRING
*"     VALUE(RESPONSE_HEADERS) TYPE  TIHTTPNVP
*"     VALUE(DATA_B64) TYPE  SOLI_TAB
*"     VALUE(DATA_LENGTH) TYPE  I
*"----------------------------------------------------------------------
*
* ABAP Web Proxy
* https://github.com/koemaeda/abap-web-proxy
*
* Copyright (c) 2017 Guilherme Maeda
* Licensed under the MIT license.
*
*"----------------------------------------------------------------------
  data(lo_request) = new zwebproxy_request(
    method = method
    uri = uri
    http_version_major = http_version_major
    http_version_minor = http_version_minor
    headers = request_headers
    post_data = cl_http_utility=>decode_x_base64( post_data_b64 )
    proxy_host = proxy_host
    proxy_port = proxy_port
    proxy_username = proxy_username
    proxy_password = proxy_password
  ).

  "// Go!
  subrc = lo_request->run( ).

  code = lo_request->response_code.
  message = lo_request->response_message.
  response_headers = lo_request->response_headers.
  data_length = xstrlen( lo_request->response_data ).

  "// base64-encode the response body
  data(lo_tb) = new cl_abap_itab_c_writer( line_type = cl_abap_typedescr=>typekind_char line_length = 255 ).
  lo_tb->write( cl_http_utility=>encode_x_base64( lo_request->response_data ) ).
  lo_tb->get_result_table( importing table = data_b64 ).
endfunction.
