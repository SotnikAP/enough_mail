import 'dart:io';
import 'dart:convert';

import '../../message_builder.dart';
import '../../mime_message.dart';
import 'package:encrypt/encrypt.dart';
import 'package:crypto/crypto.dart';

extension MailSignature on MessageBuilder {
  static final RSAKeyParser _rsaKeyParser  = RSAKeyParser();
  static const List<String> _signedHeaders = ['from'/*, 'to', 'mime-version'*/];
  static const int          _bodyLength    = 72; // Fails over >76
  static const String       _crlf          = '\r\n';
  static const String       _headerName    = 'DKIM-Signature';

  String _cleanWhiteSpaces(String target) => target.replaceAll(RegExp(r'\s+', multiLine: true), ' ');
  String _cleanLineBreaks(String target)  {
    var parts = target.replaceAll(_crlf, '\n').replaceAll('\n', _crlf).split(_crlf);
    
    for (var i = 0; i < parts.length; i++) {
      parts[i] = _cleanWhiteSpaces(parts[i]).trimRight();
    }

    return parts.join(_crlf);
  }

  int get _secondsSinceEpoch => (DateTime.now().millisecondsSinceEpoch / 1000).floor();

  Header _createDkimHeader(String body, String domain, String selector) {
    return Header(_headerName, 
      '''
        v=1; t=$_secondsSinceEpoch;
        d=$domain; s=$selector;
        h=${_signedHeaders.join(':')};
        q=dns/txt;
        l=$_bodyLength;
        c=relaxed/relaxed; a=rsa-sha256;
        bh=${_hash(body.substring(0, _bodyLength))};
        b=
      '''.replaceAll(RegExp(r'^ +', multiLine: true), '')
    );
  }

  String _hash(String target)             => base64.encode(sha256.convert(utf8.encode(target)).bytes);
  String _relaxedHeaderValue(Header head) => '${head.lowerCaseName}:${_cleanWhiteSpaces(head.value.replaceAll(RegExp(r'\r|\n'), ' ')).trim()}$_crlf';
  bool   _isSignedHeader(Header head)     => _signedHeaders.contains(head.lowerCaseName);

  String _relaxedHeader(List<Header> headers) {
    final relaxed = StringBuffer();

    for (var head in headers.where(_isSignedHeader)) {
      relaxed.write(_relaxedHeaderValue(head));
    }

    return _cleanLineBreaks(relaxed.toString());
  }
  
  // Use to see existence of escape characters
  String _debugTrace(String target) {
    print(target.replaceAll(' ', '<SP>').replaceAll('\r', '<CR>').replaceAll('\n', '<LF>\n'));
  }

  String _relaxedBody(String body) {
    body = _cleanLineBreaks(body).trimRight();

    return body.isEmpty ? '' : body + _crlf;
  }

  String _sign(String privateKey, String value) {
    return RSASigner(
      RSASignDigest.SHA256, privateKey: _rsaKeyParser.parse(privateKey)
    ).sign(utf8.encode(value)).base64;
  }

  bool sign({String privateKey, String domain, String selector}) {
    final msg       = buildMimeMessage();
    final body      = _relaxedBody(msg.renderMessage(renderHeader: false));
    final header    = _relaxedHeader(msg.headers);
    final dkim      = _relaxedHeaderValue(_createDkimHeader(body, domain, selector));
    final signature = (dkim.trim() + _sign(privateKey, (header + dkim).trim()));

    addHeader(_headerName, signature.substring(_headerName.length + 1).trim());

    return true;
  }


}