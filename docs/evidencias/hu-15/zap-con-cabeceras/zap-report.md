# ZAP Scanning Report

ZAP by [Checkmarx](https://checkmarx.com/).


## Summary of Alerts

| Risk Level | Number of Alerts |
| --- | --- |
| High | 0 |
| Medium | 1 |
| Low | 3 |
| Informational | 1 |




## Insights

| Level | Reason | Site | Description | Statistic |
| --- | --- | --- | --- | --- |
| Low | Warning |  | ZAP warnings logged - see the zap.log file for details | 1    |
| Info | Informational | http://172.17.0.2:8080 | Percentage of responses with status code 2xx | 93 % |
| Info | Informational | http://172.17.0.2:8080 | Percentage of responses with status code 3xx | 6 % |
| Info | Informational | http://172.17.0.2:8080 | Percentage of endpoints with content type application/javascript | 7 % |
| Info | Informational | http://172.17.0.2:8080 | Percentage of endpoints with content type application/octet-stream | 7 % |
| Info | Informational | http://172.17.0.2:8080 | Percentage of endpoints with content type image/x-icon | 7 % |
| Info | Informational | http://172.17.0.2:8080 | Percentage of endpoints with content type text/css | 7 % |
| Info | Informational | http://172.17.0.2:8080 | Percentage of endpoints with content type text/html | 69 % |
| Info | Informational | http://172.17.0.2:8080 | Percentage of endpoints with method GET | 100 % |
| Info | Informational | http://172.17.0.2:8080 | Count of total endpoints | 13    |







## Alerts

| Name | Risk Level | Number of Instances |
| --- | --- | --- |
| CSP: style-src unsafe-inline | Medium | Systemic |
| Cross-Origin-Embedder-Policy Header Missing or Invalid | Low | Systemic |
| Dangerous JS Functions | Low | 1 |
| Timestamp Disclosure - Unix | Low | Systemic |
| Storable and Cacheable Content | Informational | Systemic |




## Alert Detail



### [ CSP: style-src unsafe-inline ](https://www.zaproxy.org/docs/alerts/10055/)



##### Medium (High)

### Description

Content Security Policy (CSP) is an added layer of security that helps to detect and mitigate certain types of attacks. Including (but not limited to) Cross Site Scripting (XSS), and data injection attacks. These attacks are used for everything from data theft to site defacement or distribution of malware. CSP provides a set of standard HTTP headers that allow website owners to declare approved sources of content that browsers should be allowed to load on that page — covered types are JavaScript, CSS, HTML frames, fonts, images and embeddable objects such as Java applets, ActiveX, audio and video files.

* URL: http://172.17.0.2:8080
  * Node Name: `http://172.17.0.2:8080`
  * Method: `GET`
  * Parameter: `Content-Security-Policy`
  * Attack: ``
  * Evidence: `default-src 'self'; script-src 'self' 'sha256-67fhrP0+BkBqmgGGXTtgiVO/9EQs3QruYNU/7fnRkI8='; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self'; media-src 'self' blob:; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'`
  * Other Info: `style-src includes unsafe-inline.`
* URL: http://172.17.0.2:8080/admin
  * Node Name: `http://172.17.0.2:8080/admin`
  * Method: `GET`
  * Parameter: `Content-Security-Policy`
  * Attack: ``
  * Evidence: `default-src 'self'; script-src 'self' 'sha256-67fhrP0+BkBqmgGGXTtgiVO/9EQs3QruYNU/7fnRkI8='; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self'; media-src 'self' blob:; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'`
  * Other Info: `style-src includes unsafe-inline.`
* URL: http://172.17.0.2:8080/robots.txt
  * Node Name: `http://172.17.0.2:8080/robots.txt`
  * Method: `GET`
  * Parameter: `Content-Security-Policy`
  * Attack: ``
  * Evidence: `default-src 'self'; script-src 'self' 'sha256-67fhrP0+BkBqmgGGXTtgiVO/9EQs3QruYNU/7fnRkI8='; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self'; media-src 'self' blob:; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'`
  * Other Info: `style-src includes unsafe-inline.`
* URL: http://172.17.0.2:8080/sitemap.xml
  * Node Name: `http://172.17.0.2:8080/sitemap.xml`
  * Method: `GET`
  * Parameter: `Content-Security-Policy`
  * Attack: ``
  * Evidence: `default-src 'self'; script-src 'self' 'sha256-67fhrP0+BkBqmgGGXTtgiVO/9EQs3QruYNU/7fnRkI8='; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self'; media-src 'self' blob:; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'`
  * Other Info: `style-src includes unsafe-inline.`
* URL: http://172.17.0.2:8080/visitor
  * Node Name: `http://172.17.0.2:8080/visitor`
  * Method: `GET`
  * Parameter: `Content-Security-Policy`
  * Attack: ``
  * Evidence: `default-src 'self'; script-src 'self' 'sha256-67fhrP0+BkBqmgGGXTtgiVO/9EQs3QruYNU/7fnRkI8='; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self'; media-src 'self' blob:; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'`
  * Other Info: `style-src includes unsafe-inline.`

Instances: Systemic


### Solution

Ensure that your web server, application server, load balancer, etc. is properly configured to set the Content-Security-Policy header.

### Reference


* [ https://www.w3.org/TR/CSP/ ](https://www.w3.org/TR/CSP/)
* [ https://caniuse.com/#search=content+security+policy ](https://caniuse.com/#search=content+security+policy)
* [ https://content-security-policy.com/ ](https://content-security-policy.com/)
* [ https://github.com/HtmlUnit/htmlunit-csp ](https://github.com/HtmlUnit/htmlunit-csp)
* [ https://web.dev/articles/csp#resource-options ](https://web.dev/articles/csp#resource-options)


#### CWE Id: [ 693 ](https://cwe.mitre.org/data/definitions/693.html)


#### WASC Id: 15

#### Source ID: 3

### [ Cross-Origin-Embedder-Policy Header Missing or Invalid ](https://www.zaproxy.org/docs/alerts/90004/)



##### Low (Medium)

### Description

Cross-Origin-Embedder-Policy header is a response header that prevents a document from loading any cross-origin resources that don't explicitly grant the document permission (using CORP or CORS).

* URL: http://172.17.0.2:8080
  * Node Name: `http://172.17.0.2:8080`
  * Method: `GET`
  * Parameter: `Cross-Origin-Embedder-Policy`
  * Attack: ``
  * Evidence: ``
  * Other Info: ``
* URL: http://172.17.0.2:8080/circles
  * Node Name: `http://172.17.0.2:8080/circles`
  * Method: `GET`
  * Parameter: `Cross-Origin-Embedder-Policy`
  * Attack: ``
  * Evidence: ``
  * Other Info: ``
* URL: http://172.17.0.2:8080/robots.txt
  * Node Name: `http://172.17.0.2:8080/robots.txt`
  * Method: `GET`
  * Parameter: `Cross-Origin-Embedder-Policy`
  * Attack: ``
  * Evidence: ``
  * Other Info: ``
* URL: http://172.17.0.2:8080/sitemap.xml
  * Node Name: `http://172.17.0.2:8080/sitemap.xml`
  * Method: `GET`
  * Parameter: `Cross-Origin-Embedder-Policy`
  * Attack: ``
  * Evidence: ``
  * Other Info: ``
* URL: http://172.17.0.2:8080/visitor
  * Node Name: `http://172.17.0.2:8080/visitor`
  * Method: `GET`
  * Parameter: `Cross-Origin-Embedder-Policy`
  * Attack: ``
  * Evidence: ``
  * Other Info: ``

Instances: Systemic


### Solution

Ensure that the application/web server sets the Cross-Origin-Embedder-Policy header appropriately, and that it sets the Cross-Origin-Embedder-Policy header to 'require-corp' for documents.
If possible, ensure that the end user uses a standards-compliant and modern web browser that supports the Cross-Origin-Embedder-Policy header (https://caniuse.com/mdn-http_headers_cross-origin-embedder-policy).

### Reference


* [ https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Cross-Origin-Embedder-Policy ](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Cross-Origin-Embedder-Policy)


#### CWE Id: [ 693 ](https://cwe.mitre.org/data/definitions/693.html)


#### WASC Id: 14

#### Source ID: 3

### [ Dangerous JS Functions ](https://www.zaproxy.org/docs/alerts/10110/)



##### Low (Low)

### Description

A dangerous JS function seems to be in use that would leave the site vulnerable.

* URL: http://172.17.0.2:8080/_expo/static/js/web/entry-4e8840f5f61686fc26b8c70c407e632b.js
  * Node Name: `http://172.17.0.2:8080/_expo/static/js/web/entry-4e8840f5f61686fc26b8c70c407e632b.js`
  * Method: `GET`
  * Parameter: ``
  * Attack: ``
  * Evidence: `eval(`
  * Other Info: ``


Instances: 1

### Solution

See the references for security advice on the use of these functions.

### Reference


* [ https://v17.angular.io/guide/security ](https://v17.angular.io/guide/security)


#### CWE Id: [ 749 ](https://cwe.mitre.org/data/definitions/749.html)


#### Source ID: 3

### [ Timestamp Disclosure - Unix ](https://www.zaproxy.org/docs/alerts/10096/)



##### Low (Low)

### Description

A timestamp was disclosed by the application/web server. - Unix

* URL: http://172.17.0.2:8080/_expo/static/js/web/entry-4e8840f5f61686fc26b8c70c407e632b.js
  * Node Name: `http://172.17.0.2:8080/_expo/static/js/web/entry-4e8840f5f61686fc26b8c70c407e632b.js`
  * Method: `GET`
  * Parameter: ``
  * Attack: ``
  * Evidence: `1604231423`
  * Other Info: `1604231423, which evaluates to: 2020-11-01 11:50:23.`
* URL: http://172.17.0.2:8080/_expo/static/js/web/entry-4e8840f5f61686fc26b8c70c407e632b.js
  * Node Name: `http://172.17.0.2:8080/_expo/static/js/web/entry-4e8840f5f61686fc26b8c70c407e632b.js`
  * Method: `GET`
  * Parameter: ``
  * Attack: ``
  * Evidence: `1687547391`
  * Other Info: `1687547391, which evaluates to: 2023-06-23 19:09:51.`
* URL: http://172.17.0.2:8080/_expo/static/js/web/entry-4e8840f5f61686fc26b8c70c407e632b.js
  * Node Name: `http://172.17.0.2:8080/_expo/static/js/web/entry-4e8840f5f61686fc26b8c70c407e632b.js`
  * Method: `GET`
  * Parameter: ``
  * Attack: ``
  * Evidence: `1768516095`
  * Other Info: `1768516095, which evaluates to: 2026-01-15 22:28:15.`
* URL: http://172.17.0.2:8080/_expo/static/js/web/entry-4e8840f5f61686fc26b8c70c407e632b.js
  * Node Name: `http://172.17.0.2:8080/_expo/static/js/web/entry-4e8840f5f61686fc26b8c70c407e632b.js`
  * Method: `GET`
  * Parameter: ``
  * Attack: ``
  * Evidence: `2005441023`
  * Other Info: `2005441023, which evaluates to: 2033-07-20 02:57:03.`
* URL: http://172.17.0.2:8080/_expo/static/js/web/entry-4e8840f5f61686fc26b8c70c407e632b.js
  * Node Name: `http://172.17.0.2:8080/_expo/static/js/web/entry-4e8840f5f61686fc26b8c70c407e632b.js`
  * Method: `GET`
  * Parameter: ``
  * Attack: ``
  * Evidence: `2096890111`
  * Other Info: `2096890111, which evaluates to: 2036-06-12 13:28:31.`

Instances: Systemic


### Solution

Manually confirm that the timestamp data is not sensitive, and that the data cannot be aggregated to disclose exploitable patterns.

### Reference


* [ https://cwe.mitre.org/data/definitions/200.html ](https://cwe.mitre.org/data/definitions/200.html)


#### CWE Id: [ 497 ](https://cwe.mitre.org/data/definitions/497.html)


#### WASC Id: 13

#### Source ID: 3

### [ Storable and Cacheable Content ](https://www.zaproxy.org/docs/alerts/10049/)



##### Informational (Medium)

### Description

The response contents are storable by caching components such as proxy servers, and may be retrieved directly from the cache, rather than from the origin server by the caching servers, in response to similar requests from other users. If the response data is sensitive, personal or user-specific, this may result in sensitive information being leaked. In some cases, this may even result in a user gaining complete control of the session of another user, depending on the configuration of the caching components in use in their environment. This is primarily an issue where "shared" caching servers such as "proxy" caches are configured on the local network. This configuration is typically found in corporate or educational environments, for instance.

* URL: http://172.17.0.2:8080
  * Node Name: `http://172.17.0.2:8080`
  * Method: `GET`
  * Parameter: ``
  * Attack: ``
  * Evidence: ``
  * Other Info: `In the absence of an explicitly specified caching lifetime directive in the response, a liberal lifetime heuristic of 1 year was assumed. This is permitted by rfc7234.`
* URL: http://172.17.0.2:8080/admin
  * Node Name: `http://172.17.0.2:8080/admin`
  * Method: `GET`
  * Parameter: ``
  * Attack: ``
  * Evidence: ``
  * Other Info: `In the absence of an explicitly specified caching lifetime directive in the response, a liberal lifetime heuristic of 1 year was assumed. This is permitted by rfc7234.`
* URL: http://172.17.0.2:8080/robots.txt
  * Node Name: `http://172.17.0.2:8080/robots.txt`
  * Method: `GET`
  * Parameter: ``
  * Attack: ``
  * Evidence: ``
  * Other Info: `In the absence of an explicitly specified caching lifetime directive in the response, a liberal lifetime heuristic of 1 year was assumed. This is permitted by rfc7234.`
* URL: http://172.17.0.2:8080/sitemap.xml
  * Node Name: `http://172.17.0.2:8080/sitemap.xml`
  * Method: `GET`
  * Parameter: ``
  * Attack: ``
  * Evidence: ``
  * Other Info: `In the absence of an explicitly specified caching lifetime directive in the response, a liberal lifetime heuristic of 1 year was assumed. This is permitted by rfc7234.`
* URL: http://172.17.0.2:8080/visitor
  * Node Name: `http://172.17.0.2:8080/visitor`
  * Method: `GET`
  * Parameter: ``
  * Attack: ``
  * Evidence: ``
  * Other Info: `In the absence of an explicitly specified caching lifetime directive in the response, a liberal lifetime heuristic of 1 year was assumed. This is permitted by rfc7234.`

Instances: Systemic


### Solution

Validate that the response does not contain sensitive, personal or user-specific information. If it does, consider the use of the following HTTP response headers, to limit, or prevent the content being stored and retrieved from the cache by another user:
Cache-Control: no-cache, no-store, must-revalidate, private
Pragma: no-cache
Expires: 0
This configuration directs both HTTP 1.0 and HTTP 1.1 compliant caching servers to not store the response, and to not retrieve the response (without validation) from the cache, in response to a similar request.

### Reference


* [ https://datatracker.ietf.org/doc/html/rfc7234 ](https://datatracker.ietf.org/doc/html/rfc7234)
* [ https://datatracker.ietf.org/doc/html/rfc7231 ](https://datatracker.ietf.org/doc/html/rfc7231)
* [ https://www.w3.org/Protocols/rfc2616/rfc2616-sec13.html ](https://www.w3.org/Protocols/rfc2616/rfc2616-sec13.html)


#### CWE Id: [ 524 ](https://cwe.mitre.org/data/definitions/524.html)


#### WASC Id: 13

#### Source ID: 3


