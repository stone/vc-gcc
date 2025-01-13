vcl 4.1;

import goto;
import std;
import ykey;

# For SSL offloading, pass the following header in your proxy server or load balancer: '/* {{ ssl_offloaded_header }} */: https'

backend default none;

probe p1 {
        .url = "/pub/health_check.php";
        .timeout = 2s;
        .interval = 5s;
        .window = 10;
        .threshold = 5;
}

acl purge {
/* {{ ips }} */
}

sub vcl_init {
    new dir = goto.dns_director("0.0.0.0:80",
                                probe = p1,
                                first_byte_timeout = 10m);
}

sub vcl_recv {
    set req.backend_hint = dir.backend();

    if (req.method == "PURGE") {
        if (client.ip !~ purge) {
            return (synth(405, "Method not allowed"));
        }
        # To use the X-Pool header for purging varnish during automated deployments, make sure the X-Pool header
        # has been added to the response in your backend server config. This is used, for example, by the
        # capistrano-magento2 gem for purging old content from varnish during it's deploy routine.
        if (!req.http.X-Magento-Tags-Pattern && !req.http.X-Pool) {
            return (synth(400, "X-Magento-Tags-Pattern or X-Pool header required"));
        }
        if (req.http.X-Magento-Tags-Pattern) {
            set req.http.X-Magento-Tags-Pattern = regsuball(req.http.X-Magento-Tags-Pattern, "\(\(\^\|\,\)", " ");
            set req.http.X-Magento-Tags-Pattern = regsuball(req.http.X-Magento-Tags-Pattern, "\(\,\|\$\)\)", "");
            set req.http.X-Magento-Tags-Pattern = regsuball(req.http.X-Magento-Tags-Pattern, "\|", ",");
            ykey.purge_keys(req.http.X-Magento-Tags-Pattern);
        }
        if (req.http.X-Pool) {
            set req.http.X-Pool = regsuball(req.http.X-Pool, "\(\(\^\|\,\)", " ");
            set req.http.X-Pool = regsuball(req.http.X-Pool, "\(\,\|\$\)\)", "");
            set req.http.X-Pool = regsuball(req.http.X-Pool, "\|", ",");
            ykey.namespace("pool");
            ykey.purge_keys(req.http.X-Pool);
            ykey.namespace_reset();
        }
        return (synth(200, "Purged"));
    }

    if (req.method != "GET" &&
        req.method != "HEAD" &&
        req.method != "PUT" &&
        req.method != "POST" &&
        req.method != "TRACE" &&
        req.method != "OPTIONS" &&
        req.method != "DELETE") {
          /* Non-RFC2616 or CONNECT which is weird. */
          return (pipe);
    }

    # We only deal with GET and HEAD by default
    if (req.method != "GET" && req.method != "HEAD") {
        return (pass);
    }

    # Bypass customer, shopping cart, checkout
    if (req.url ~ "/customer" || req.url ~ "/checkout") {
        return (pass);
    }

    # Bypass health check requests
    if (req.url ~ "^/(pub/)?(health_check.php)$") {
        return (pass);
    }

    # if the backend is healthy, limit the grace
    if (std.healthy(req.backend_hint)) {
        set req.grace = 100s;
        set req.http.grace = "normal (healthy server)";
    } else {
        set req.http.grace = "unlimited (unhealthy server)";
    }

    set req.http.grace = "none";

    # normalize url in case of leading HTTP scheme and domain
    set req.url = regsub(req.url, "^http[s]?://", "");

    # collect all cookies
    std.collect(req.http.Cookie);

    # Remove all marketing get parameters to minimize the cache objects
    if (req.url ~ "(\?|&)(gclid|cx|ie|cof|siteurl|zanpid|origin|fbclid|mc_[a-z]+|utm_[a-z]+|_bta_[a-z]+)=") {
        set req.url = regsuball(req.url, "(gclid|cx|ie|cof|siteurl|zanpid|origin|fbclid|mc_[a-z]+|utm_[a-z]+|_bta_[a-z]+)=[-_A-z0-9+()%.]+&?", "");
        set req.url = regsub(req.url, "[?|&]+$", "");
    }

    # Static files caching
    if (req.url ~ "^/(pub/)?(media|static)/") {
        # Static files should not be cached by default
        return (pass);

        # But if you use a few locales and don't use CDN you can enable caching static files by commenting previous line (#return (pass);) and uncommenting next 3 lines
        #unset req.http.Https;
        #unset req.http.Cookie;
    }

    # Authenticated GraphQL requests should not be cached by default
    if (req.url ~ "/graphql" && req.http.Authorization ~ "^Bearer") {
        return (pass);
    }

    return (hash);
}

sub vcl_hash {
    if (req.http.cookie ~ "X-Magento-Vary=") {
        hash_data(regsub(req.http.cookie, "^.*?X-Magento-Vary=([^;]+);*.*$", "\1"));
    } else {
    	hash_data("");
    }


    if (req.url ~ "/graphql") {
        hash_data(req.http.Store);
        hash_data(req.http.Content-Currency);
    }
}

sub vcl_backend_response {
    # tag the object to purge it later
    ykey.add_header(beresp.http.X-Magento-Tags);
    ykey.namespace("pool");
    ykey.add_header(beresp.http.X-Pool);
    ykey.namespace_reset();

    set beresp.grace = 3d;

    if (beresp.http.content-type ~ "text") {
        set beresp.do_esi = true;
    }

    if (bereq.url ~ "\.js$" || beresp.http.content-type ~ "text") {
        set beresp.do_gzip = true;
    }

    if (beresp.http.X-Magento-Debug) {
        set beresp.http.X-Magento-Cache-Control = beresp.http.Cache-Control;
    }

    # cache only successfully responses and 404s
    if (beresp.status != 200 && beresp.status != 404) {
        set beresp.ttl = 120s;
        set beresp.uncacheable = true;
        return (deliver);
    } elsif (beresp.http.Cache-Control ~ "private") {
        set beresp.uncacheable = true;
        set beresp.ttl = 86400s;
        return (deliver);
    }

    # validate if we need to cache it and prevent from setting cookie
    if (beresp.ttl > 0s && (bereq.method == "GET" || bereq.method == "HEAD")) {
        unset beresp.http.set-cookie;
    }

   # If page is not cacheable then bypass varnish for 2 minutes as Hit-For-Pass
   if (beresp.ttl <= 0s ||
       beresp.http.Surrogate-control ~ "no-store" ||
       (!beresp.http.Surrogate-Control &&
       beresp.http.Cache-Control ~ "no-cache|no-store") ||
       beresp.http.Vary == "*") {
        # Mark as Hit-For-Pass for the next 2 minutes
        set beresp.ttl = 120s;
        set beresp.uncacheable = true;
    }

    return (deliver);
}

sub vcl_deliver {
    if (resp.http.X-Magento-Debug) {
        if (obj.uncacheable) {
            set resp.http.X-Magento-Cache-Debug = "UNCACHEABLE";
        } else if (obj.hits) {
            set resp.http.X-Magento-Cache-Debug = "HIT";
            set resp.http.Grace = req.http.grace;
        } else {
            set resp.http.X-Magento-Cache-Debug = "MISS";
        }
    } else {
        unset resp.http.Age;
    }

    # Not letting browser to cache non-static files.
    if (resp.http.Cache-Control !~ "private" && req.url !~ "^/(pub/)?(media|static)/") {
        set resp.http.Pragma = "no-cache";
        set resp.http.Expires = "-1";
        set resp.http.Cache-Control = "no-store, no-cache, must-revalidate, max-age=0";
    }

    unset resp.http.X-Magento-Debug;
    unset resp.http.X-Magento-Tags;
    unset resp.http.X-Powered-By;
    unset resp.http.Server;
    unset resp.http.X-Varnish;
    unset resp.http.Via;
    unset resp.http.Link;
}

sub vcl_hit {
    # Hit within TTL period
    if (obj.ttl >= 0s) {
        set req.http.grace = "none";
        return (deliver);
    }
}
