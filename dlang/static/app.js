var user;

class HTTP {
  get(url, data) {
    if (data) {
      url += '?';
      url += Object.keys(data)
        .map((k) => encodeURIComponent(k) + "=" + encodeURIComponent(data[k]));
    }
    return this.req("GET", url, null);
  }

  put(url, data) {
    return this.req("PUT", url, data);
  }

  post(url, data) {
    return this.req("POST", url, data);
  }

  req(method, url, data) {
    return new Promise((resolve, reject) => {
      let xhr = new XMLHttpRequest();
      xhr.open(method, url);
      xhr.onload = () => {
        try {
          resolve({xhr: xhr, body: JSON.parse(xhr.response)});
        } catch (e) {
          reject(e);
        }
      };
      xhr.on = () => {
        reject(xhr);
      };
      xhr.send(JSON.stringify(data));
    });
  }
}

class Feeds {
  constructor() {
    this.http = new HTTP();
  }

  grabArticles(unreadOnly, startDate, endDate) {
    return this.http.get(`/feeds/articles?unreadOnly=${unreadOnly}&newerThan=${startDate}&olderThan=${endDate}`);
  }

  grabAllArticles(unreadOnly, afterDate, storage) {
    if (!storage) {
      storage = [];
    }
    return this.grabArticles(unreadOnly, afterDate, null)
      .then((arts) => {
        if (arts.length == 0) {
          return storage;
        }
        storage.splice(storage.length, 0, arts);
        return grabAllArticles(unreadOnly, arts[arts.length - 1].publishDate, storage);
      });
  }
}

let feeds = new Feeds();

var domain = {
  // raw feeds (none of the tag-aggregated feeds)
  realFeeds: [],
  labels: [],
  subscriptions: [],

  /********* Read-only properties. ***********/
  getArticles: function() {
    if (ui.currentFeed) {
      return ui.currentFeed.articles;
    } else if (ui.currentLabel) {
      return ui.currentLabel.articles;
    } else {
      return [];
    }
  },

  getSubscription: function(feedId) {
    if (!domain.subscriptions) return;
    for (var i = 0; i < domain.subscriptions.length; i++) {
      if (domain.subscriptions[i].feedId == feedId) {
        return domain.subscriptions[i];
      }
    }
    return null;
  },

  getFeed: function(feedId) {
    if (!domain.feeds) {
      return null;
    }
    for (var i = 0; i < domain.feeds.length; i++) {
      if (domain.feeds[i].id == feedId) {
        return domain.feeds[i];
      }
    }
    return null;
  },

  getArticle: function(feed, artId) {
    for (var i = 0; i < feed.articles.length; i++) {
      if (feed.articles[i].id == artId) {
        return feed.articles[i];
      }
    }
    return null;
  },

  // Get a label object based on the label name (eg 'Yogscast' -> {title: 'Yogscast', ...})
  getLabel: function(labelId) {
    for (var i = 0; i < domain.labels.length; i++) {
      if (domain.labels[i].id == labelId) {
        return domain.labels[i];
      }
    }
    return null;
  },

  // Get the number of unread articles in the given feed or label.
  unreadCount: function(feed) {
    var articles = feed.articles;
    if (!articles) return 0;
    var unread = 0;
    for (var i = 0; i < articles.length; i++) {
      if (!articles[i].IsRead) {
        unread++;
      }
    }
    return unread;
  },

  /********* Constructive properties. ***************/
  buildLabels: function() {
    var lab = new Map()
    var unlisted = [];
    domain.realFeeds.forEach((feed) => {
      var sub = domain.getSubscription(feed.id);
      var labels = sub ? sub.labels : [];
      if (labels.length) {
        labels.forEach((name) =>  {
          var e = lab.get(name);
          if (e) {
            e.feeds.push(feed);
          } else {
            lab.set(name, {
              title: name,
              id: 'label_' + util.safeId(name),
              feeds: [feed],
              label: name,
              autogenerated: true,
            });
          }
        });
      } else {
        unlisted.push(feed);
      }
    });

    var lablist = [];
    lab.forEach((k, label) => lablist.push(label));

    domain.allList = {
      title: 'All',
      id: 'special_label_All',
      feeds: domain.realFeeds,
      autogenerated: true,
    };
    lablist.sort(function(a, b) {
      if (a.title < b.title) return -1;
      if (a.title > b.title) return 1;
      return 0;
    });
    lablist = [domain.allList].concat(lablist);
    domain.updateLabelUnreadCounts(lablist);

    if (unlisted.length) {
      lablist.push({
        title: 'Uncategorized',
        id: 'special_label_Uncategorized',
        feeds: unlisted,
        autogenerated: true,
      });
    }
    $.each(lablist, function(k, label) {
      util.sortFeeds(label.feeds);
      if (label.feeds) {
        label.articles = domain.buildCombinedArticles(label.feeds, label);
      } else {
        console.log(`label ${label.title} has no feeds!`);
      }
    });

    domain.labels = lablist;
    ui.displayFeeds();
  },

  buildCombinedArticles: function(feeds, label) {
    var combined = [];
    if (feeds) {
      for (var i = 0; i < feeds.length; i++) {
        combined = combined.concat(feeds[i].articles);
      }
    } else {
      console.log(`failed to build combined articles for ${label}`);
    }
    util.sortArticles(combined);
    return combined;
  },

  /*********** Updating, or munging input. *************/
  mungeArticle: function(article) {
    article.publishDate = util.jsDate(article.publishDate);
    article.feed = domain.feedsByID.get(article.feedId);
    article.title = (article.title || '').replace(/<[^>]*>/g, '');
    article.display = ui.buildArticleDisplay(article);
    // TODO figure out whether article is read or not
    // If we got it from unreadOnly=true, it's unread; otherwise, dunno
    if (article.isRead === null || article.isRead === undefined) {
      article.isRead = false;
    }
  },

  refreshUser: function() {
    view.hideUnknownError();
    view.hideLoginWindow();
    console.log('refreshing user data');
    ui.showAlert('Refreshing subscriptions');
    $.ajax('/users/self', {
      dataType: 'json',
      success: function(data, statusText, xhr) {
        console.log('success refreshing user data');
        user = data;
        ui.updateUserInfos();
        console.log('about to refresh feeds');
        domain.refreshFeeds();
      },
      error: function(xhr, status, err) {
        console.log('error refreshing user data: ' + err);
        view.hideUnknownError();
        view.hideLoginWindow();
        if (xhr.status == 401 || xhr.status == 404) {
          view.showLoginWindow();
        } else {
          view.showUnknownError();
        }
      }
    });
  },

  refreshSubsImpl: function(last, subs, after) {
    $.ajax('/users/subscriptions', {
      dataType: 'json',
      method: 'GET',
      data: {last: last},
      success: function(data) {
        subs.subscriptions = subs.subscriptions.concat(data.subscriptions);
        subs.feeds = subs.feeds.concat(data.subscriptions);
        if (data.next) {
          refreshSubsImpl(data.next, subs, after);
        } else {
          after(subs);
        }
      }
    });
  },

  refreshSubs: function(after) {
    let subs = {subscriptions: [], feeds: []};
    let last = '';
    domain.refreshSubsImpl(last, subs, after);
  },

  refreshFeeds: function() {
    // TODO progress indicators?
    ui.showAlert("Refreshing subscription list...");
    domain.refreshSubs((data) => {
      console.log('found ' + data.subscriptions.length + ' subscriptions');
      console.log(data);
      domain.subscriptions = data.subscriptions;
      console.log(`found ${data.feeds.length} feeds`);
      domain.realFeeds = data.feeds;
      domain.feedsByID = new Map();
      domain.realFeeds.forEach((f) => domain.mungeFeed(f));
      domain.realFeeds.forEach((f) => domain.feedsByID.set(f.id, f));
      domain.reloadFeedInfo();
      ui.updateTitle();

      ui.showAlert("Refreshing articles...");
      feeds.grabArticles(showingUnreadOnly, null, null, (articles) => {
        articles.forEach(domain.mungeArticle);
        domain.articles = articles;
        ui.updateTitle();
        ui.showAlert("Done!");
        window.setTimeout(() => ui.hideAlert(), 3000);
      });
    });
  },

  mungeFeed: function(feed) {
    if (typeof feed.labels === "string") {
      feed.labels = feed.labels.split(",");
    } else if (!feed.labels) {
      feed.labels = [];
    }
    console.log(`mungeFeed(${feed.title}): labels now ${feed.labels}`);
    console.log(feed);
  },

  refreshFeed: function(feedId) {
    $.ajax('/feeds/refresh_now', {
      method: 'POST',
      data: {
        id: feedId
      },
      success: function(data, a, b) {
        domain.updateFeed(data);
      }
    });
  },

  reloadFeedInfo: function() {
    domain.feeds = [].concat(domain.realFeeds);
    util.sortFeeds(domain.feeds);
    domain.buildLabels();
    ui.displayFeeds();
    if (!ui.currentFeed && !ui.currentLabel) {
      ui.currentLabel = domain.allList;
    }
    if (ui.currentFeed) {
      ui.showFeed(ui.currentFeed.id);
    } else if (ui.currentLabel) {
      ui.showLabel(ui.currentLabel.id)
    }
    ui.updateTitle();
  },

  /********* Modifying data ************/
  updateFeed: function(feed) {
    domain.mungeFeed(feed);
    for (var i = 0; i < domain.realFeeds.length; i++) {
      if (domain.realFeeds[i].id == feed.id) {
        domain.realFeeds[i] = feed;
        break;
      }
    }
    domain.reloadFeedInfo();
  },

  removeFeed: function(feedId) {
    var feed = domain.getFeed(feedId);
    if (feed == null) return;
    if (feed.Autogenerated) return;
    domain.realFeeds.splice(domain.realFeeds.indexOf(feed), 1);
    domain.buildLabels();
  },

  updateLabelUnreadCounts: function(labels) {
    labels.forEach((label) => {
      let unread = 0;
      label.feeds.forEach((feed) => {
        unread += feed.unreadCount;
      });
      label.unreadCount = unread;
    });
  },

  markRead: function(article) {
    if (article == null) {
      article = domain.currentArticle;
    }
    if (article == null) {
      return;
    }
    article.isRead = true;
    article.feed.unreadCount--;
    domain.updateLabelUnreadCounts(domain.labels);
    domain.getSubscription(article.feed.id).ReadArticles.push(article.id);
    $.ajax('/feeds/mark_read', {
      dataType: 'json',
      method: 'POST',
      data: {
        feedId: article.Feed.id,
        articleId: article.id
      }
    });

    domain.updateDisplayForArticle(article);
  },

  markOlderRead: function(article) {
    if (article == null) {
      article = domain.currentArticle;
    }
    if (article == null) {
      return;
    }
    $.ajax('/feeds/mark_older_read', {
      dataType: 'json',
      method: 'POST',
      data: {
        feedId: article.Feed.id,
        articleId: article.id
      }
    });

    ui.showAlert('Refresh to see updated view.');
  },

  updateDisplayForArticle: function(article) {
    ui.displayArticleStatus(article);

    // Update the real, direct feed that contains this article.
    ui.updateFeedDisplay(article.Feed);

    for (var i = 0; i < domain.feeds.length; i++) {
      var f = domain.feeds[i];
      if (f.Autogenerated) {
        if (f.Feeds != null && f.Feeds.indexOf(article.Feed) > -1) {
          ui.updateFeedDisplay(f);
        }
      }
    }

    ui.updateTitle();
  },

  markUnread: function(article) {
    if (article == null || article == undefined) {
      article = domain.currentArticle;
    }
    if (article == null || article == undefined) {
      return;
    }
    article.IsRead = false;
    article.Feed.UnreadCount++;
    domain.updateLabelUnreadCounts(domain.labels);
    var readArticles = domain.getSubscription(article.Feed.id).ReadArticles;
    var i = readArticles.indexOf(article.id);
    if (i > -1) {
      readArticles.splice(i, 1);
    }
    $.ajax('/feeds/mark_read', {
      dataType: 'json',
      data: {
        feedId: article.Feed.id,
        articleId: article.id
      }
    });

    domain.updateDisplayForArticle(article);
  },

  modifyFeed: function(feedId, title, checkInterval, labels) {
    $.ajax('/feeds/update', {
      data: {
        id: feedId,
        title: title,
        checkIntervalSeconds: checkInterval * 60,
        labels: labels
      },
      success: function(res, foo, bar) {
        var feed = domain.getFeed(feedId);
        var sub = domain.getSubscription(feedId);
        sub.title = res.Subscription.title;
        sub.checkInterval = res.Subscription.checkInterval.TotalSeconds;
        feed.ReadInterval = res.Feed.ReadInterval.TotalSeconds;
        if (labels) {
          sub.Labels = labels.split(',');
        }
        if (sub.title) {
          feed.title = sub.title;
        }
        view.closeModifyFeedWindow();
        domain.buildLabels();
        ui.displayFeeds();
      }
    });
  },

  unsubscribe: function(feedId) {
    $.ajax('/feeds/unsubscribe', {
      data: { id: feedId },
    success: function() {
      ui.showAlert('Successfully unsubscribed.');
      view.closeModifyFeedWindow();
      domain.removeFeed(feedId);
      ui.displayFeeds();
    }
    });
  },

  applyUserSettings: function(email, newPassword, currentPassword) {
    $.ajax('/users/update', {
      method: 'POST',
      data: {
        email: email,
        currentPassword: currentPassword,
        newPassword: newPassword
      },
      success: function(data) {
        if (data['Error']) {
          ui.showAlert(data['Error']);
        } else {
          view.closeSettingsWindow();
        }
      }
    });
  },

  /********** Moving **********/
  _moveArticle: function(offset) {
    // This should respect the current filters about read/unread articles.
    var f = ui.currentFeed || ui.currentLabel;
    if (!f) {
      f = domain.allList;
      if (!f) return;
    }
    if (!f.articles) {
      return;
    }
    var articleIndex = null;
    var currentArticle = domain.currentArticle;
    if (currentArticle) {
      for (var i = 0; i < f.articles.length; i++) {
        if (f.articles[i].id == currentArticle.id) {
          articleIndex = i;
          break;
        }
      }
      if (articleIndex === null) {
        // We're not showing any article in the current label / feed.
        return;
      }
      var index = articleIndex + offset;
      while (true) {
        if (index < 0 || index >= f.articles.length) {
          return;
        }
        if (!ui.isArticleVisible(f.articles[index])) {
          index += offset;
          continue;
        }
        ui.showArticle(f, f.articles[index]);
        return;
      }
    }
  },

  _moveFeed: function(offset, movingLabel) {
    var currentFeed = ui.currentFeed;
    if (!currentFeed && !movingLabel) {
      domain._moveLabel(offset);
      return;
    }
    var label = ui.currentLabel;
    if (!label) {
      label = domain.allList;
    }
    // We *need* to track what label we're in. This is going to go in a strange order.
    var index = offset < 0 ? label.Feeds.length - 1 : 0;
    if (currentFeed) {
      for (var i = 0; i < label.Feeds.length; i++) {
        if (label.Feeds[i].id == currentFeed.id) {
          index = i + offset;
          break;
        }
      }
    }
    while (true) {
      if (index < 0 || index >= label.Feeds.length) {
        console.log('got index ' + index + ' which is out of bounds')
        domain._moveLabel(offset);
        return;
      }
      var f = label.Feeds[index];
      if (f.UnreadCount == 0 && ui.showingUnreadOnly) {
        index += offset;
        continue;
      }
      ui.showFeed(f.id, label.id);
      var ai = (offset < 0) ? f.articles.length - 1 : 0;
      while (ai >= 0
          && ai < f.articles.length
          && (f.articles[ai].IsRead || !ui.showingUnreadOnly)) {
        ai += offset;
      }
      var art = f.articles[ai];
      if (art) {
        ui.showArticle(f, f.articles[ai]);
      }
      return;
    }
  },

  _moveLabel: function(offset) {
    if (!ui.currentLabel) {
      ui.showLabel(domain.allList);
      return;
    }
    var moveFeed = ui.currentFeed != null;
    var curr = ui.currentLabel.id;
    for (var i = 0; i < domain.labels.length; i++) {
      if (curr == domain.labels[i].id) {
        var k = i + offset;
        while (k >= 0 && k < domain.labels.length && !domain.labels[k].articles) {
          k += offset;
        }
        if (k < 0 || k >= domain.labels.length) {
          return;
        }
        var label = domain.labels[k];
        ui.showLabel(label.id);
        if (!ui.isExpanded(label.id)) {
          ui.toggleExpanded(label.id);
        }
        if (moveFeed) {
          domain._moveFeed(offset, true);
        }
        return;
      }
    }
  },

  previousArticle: function() {
    domain._moveArticle(-1);
  },

  nextArticle: function() {
    domain._moveArticle(1);
  },

  previousFeed: function() {
    domain._moveFeed(-1);
  },

  nextFeed: function() {
    domain._moveFeed(1);
  },

  /********** Misc ************/
  showingArticle: function(article) {
    domain.currentArticle = article;
    if (!article.IsRead) {
      domain.markRead(article);
      ui.displayFeeds();
      ui.updateTitle();
    }
  },

  initialize: function() {
    window.setInterval(domain.refreshUser, 15 * 60 * 1000);
  }
};

var ui = {
  _expandedLabels: [],
  showingPopup: false,

  isExpanded: function(label) {
    return ui._expandedLabels.indexOf(label) >= 0;
  },

  toggleExpanded: function(labelId) {
    if (ui.isExpanded(labelId)) {
      ui._expandedLabels.splice(ui._expandedLabels.indexOf(labelId), 1);
      $('#labelBox_' + labelId).removeClass('expanded');
      $('#labelBox_' + labelId).addClass('collapsed');
    } else {
      ui._expandedLabels.push(labelId);
      $('#labelBox_' + labelId).addClass('expanded');
      $('#labelBox_' + labelId).removeClass('collapsed');
    }
    localStorage.expandedLabels = JSON.stringify({ labels: ui._expandedLabels });
  },

  closeFeedPopup: function() {
    view.closeFeedWindow();
  },

  _templates: {},

  template: function(name, data) {
    var templ = $('script#' + name);
    if (!templ) {
      return 'TEMPLATE ' + name + ' NOT FOUND';
    }

    var compiled = ui._templates[name];
    if (!compiled) {
      compiled = _.template(templ.text(), {variable: 'data'});
      ui._templates[name] = compiled;
    }

    // Have to trim template text in order not to give jquery a hissy fit.
    try {
      var raw = compiled(data);
      return raw
        .replace(/^\s+/g, '')
        .replace(/\s+$/g, '');
    } catch (e) {
      console.log(`failed to run template ${name}`);
      console.log(data);
      throw e;
    }
  },

  resizeMainPanel: function() {
    $('#mainPanel').height($(window).height() - $('#headerBar').height());
    $('#mainPanel').width($(window).width());
  },

  updateUserInfos: function() {
    $('#userName').text(user.Email);
  },

  showUpdateFeedWindow: function(feedId) {
    var feed = domain.getFeed(feedId);
    var sub = domain.getSubscription(feedId);
    view.showUpdateFeedWindow(feed, sub);
  },

  displayFeeds: function() {
    if (!ui.currentFeed && !ui.currentLabel) {
      ui.currentLabel = domain.allLabel;
    }
    var contents = ui.template('labelListTemplate', {labels: domain.labels});
    $('.feedList .content').html(contents);
    ui.updateTitle();
  },

  updateFeedDisplay: function(feed) {
    $('.feedli_' + feed.id).replaceWith(ui.template('feedli', {feed: feed}));
  },

  showingUnreadOnly: true,
  currentFeed: null,

  showLabel: function(labelId) {
    var label = domain.getLabel(labelId);
    if (!label) return;
    ui.currentFeed = null;
    ui.currentLabel = label;
    ui.showArticles(domain.buildCombinedArticles(label.feeds));
    ui.selected('#labelName_' + labelId);
    ui.refreshShowingUnread();
  },

  selected: function(query) {
    $('.labelName').removeClass('selectedItem');
    $('.feedRow').removeClass('selectedItem');
    $('.feedli').removeClass('selectedItem');
    $(query).addClass('selectedItem');
  },

  showFeed: function(feedId, labelId) {
    if (!labelId) {
      if (!ui.currentLabel) {
        ui.currentLabel = domain.allList;
      }
      labelId = ui.currentLabel.id;
    }
    var feed = domain.getFeed(feedId);
    if (!feed) return;
    ui.currentFeed = feed;
    ui.currentLabel = domain.getLabel(labelId);
    ui.showArticles(feed.articles);
    ui.selected('.lf_' + feedId + labelId);
    ui.refreshShowingUnread();
  },

  buildArticleDisplay: function(article) {
    var div = document.createElement('div');
    div.id = util.articleId(article);
    if (article.IsRead) {
      div.className = 'articleli read';
    } else {
      div.className = 'articleli unread';
    }
    div.addEventListener('click', function() {
      ui.showArticle(article.Feed.id, article);
    });
    div.innerHTML =
      '<img style="height: 16px; width: 16px;" src="' + ui.iconUrl(article.Feed) + '" />'
        + ui.fmtDate(article.publishDate)
        + ' '
        + article.title;
    return div;
  },

  showArticles: function(articles) {
    ui.articles = articles;
    $('#articleList .content').empty();
    $('.articleCaution').hide();
    var before = new Date();
    // At first we were using a template for each list item and appending them individually.
    // That was outrageously slow. 16 seconds to display 3800 articles. Just no.
    //
    // When we switched to one template for the whole article list, we got down to 8 seconds. Still
    // not good enough.
    //
    // We tried caching the compiled templates, which might be a good idea generally, but apparently
    // that took so little time that normal variance between runs was larger and it was as if we
    // hadn't done it at all. We're still caching templates.
    //
    // We changed to use hard-coded string manipulation and .innerHTML. Down to 5.5 seconds. Still
    // crud. Takeaway, though: templates are a little slow. Not absurdly, just a bit.
    //
    // Finally we pre-computed the article lis for each article (which is a tad expensive) and then
    // just appended them all. This got us down to ~1.3s (plus extra startup time, but since I leave
    // it open most of the time...).
    //
    // Side note: we also tried adding the articles to a new div and then appending that to the
    // list. That cost us almost a second. So don't do that.
    var list = $('#articleList .content')[0];
    var unread = 0;
    for (var i = 0; i < articles.length; i++) {
      // Purists might suggest we clone the DOM node before using it, but this seems not to produce
      // problems in practice (plus it means I don't have to update read/unread status in two
      // separate places). Main problem: this might not do the right thing if the feed gets updated
      // and has a new icon. I think I can live with that.
      let art = articles[i];
      if (ui.showingUnreadOnly && art.IsRead) {
        // By defaulting to unread only and not building / adding things that aren't being
        // displayed, we cut render time from 8.6s to 0.028s.
        continue;
      }
      if (!art.display) {
        art.display = ui.buildArticleDisplay(art);
      }
      list.appendChild(art.display);
      if (!art.IsRead) {
        unread++;
      }
    }
    var after = new Date();
    var duration = after.getTime() - before.getTime();
    console.log('showed ' + articles.length + ' articles in ' + duration + 'ms');
    if (articles.length == 0) {
      $('#noArticles').show();
    } else if (ui.showingUnreadOnly && unread == 0) {
      $('#showingUnreadOnly').show();
    }
    ui.updateTitle();
  },

  showAlert: function(content) {
    if (ui.butterTimeout) {
      window.clearTimeout(ui.butterTimeout);
    }
    ui.butterTimeout = window.setTimeout(ui.hideAlert, 5000);
    document.getElementById('buttercontent').innerText = content;
    document.getElementById("butterbar").style.display = 'block';
  },

  hideAlert: function() {
      document.getElementById("butterbar").style.display = 'none';
  },

  displayArticleStatus: function(article) {
    var artDiv = $('#' + util.articleId(article));
    if (article.IsRead) {
      artDiv.removeClass('unread');
      artDiv.addClass('read');
    } else {
      artDiv.addClass('unread');
      artDiv.removeClass('read');
    }
  },

  showArticle: function(o, article) {
    var feed = null;
    if (o.articles) {
      feed = o;
    } else {
      feed = domain.getFeed(o) || domain.getLabel(o);
    }
    if (!article.id) {
        article = domain.getArticle(feed, article);
    }
    if (!article) {
      console.log('feed ' + feedId + ' has no article ' + artId);
      return;
    }
    if (ui.currentArticle) {
        $(ui.currentArticle).removeClass('selectedItem');
    }
    ui.currentArticle = article.display;
    var artDiv = $(article.display);
    artDiv.addClass('selectedItem');
    artDiv.removeClass('unread');
    artDiv.addClass('read');

    // pos: position *relative to scrolled viewport*
    var pos = artDiv.position();
    var par = artDiv.parent();
    // Always show an extra article above or below.
    var margin = artDiv.height() + 2;
    if (pos.top < margin) {
      var alreadyHidden = par.scrollTop();
      // we're hiding 300px
      // relative to hidden, item is at -50
      // need to scroll to 250 hidden, and a bit further up for margin
      par.scrollTop(par.scrollTop() + pos.top - margin);
    } else if (pos.top > par.height() - margin) {
      // now we want the entry as the last thing there
      // that means we hide fewer pixels -- par.height() fewer means our entry is the first thing
      // below the fold, so we raise it up by one artDiv height
      par.scrollTop(par.scrollTop() - par.height() + pos.top + margin + artDiv.height());
    }

    try {
      $('#articleView .content').html(ui.template('articlefull', {
        feed: article.Feed,
        article: article
      }));
    } catch (e) {
      console.log("error while displaying article " + article.id + ": " + e);
    }

    $('#articleView a').attr('target', '_blank');

    $('#articleTitle').text(article.Feed.title);
    domain.showingArticle(article);
    ui.updateTitle();
    $('#articleContent').focus().scrollTop(0);
  },

  toggleUnreadOnly: function() {
    ui.showingUnreadOnly = !ui.showingUnreadOnly;
    ui.showArticles(ui.articles);
    ui.refreshShowingUnread();
  },

  // We precompute article lis for speed.
  // Whenever we do this, we lose whether read articles are shown or hidden.
  // So when we finish displaying / refreshing a feed, redo show/hide stuff.
  refreshShowingUnread: function() {
    if (ui.showingUnreadOnly) {
      $('.read:not(.selectedItem)').hide();
      $('#toggleUnread').text('Unread');
    } else {
      $('.read').show();
      $('#toggleUnread').text('All');
    }
  },

  addFeed: function() {
    var url = $('#addFeedUrl').val();
    var title = $('#addFeedTitle').val();
    var labelString = $('#addFeedLabels').val();
    $.ajax('/feeds/add', {
      dataType: 'json',
      method: 'POST',
      data: {
        url: url,
        title: title,
        labels: labelString
      },
      success: function(data, statusText, xhr) {
        if (!data['success']) {
          // leave window open for corrections
          ui.showAlert('I didn\'t find any feeds :(');
        } else if (data['added_feed']) {
          // mungeFeed requires an existing subscription. Deal with it first.
          var sub = data['feed_id'];
          if (sub) {
            domain.subscriptions.push(sub);
          }
          var added = data['added_feed'];
          ui.closeFeedPopup();
          if (domain.getFeed(added.id)) return;
          domain.mungeFeed(added);
          domain.realFeeds.push(added);
          domain.reloadFeedInfo();
          ui.displayFeeds();
        } else {
          $('#multifeedOptions').empty();
          $('#addFeedUrl').val(data['feeds'][0].url);
          $.each(data['feeds'], function(i, feed) {
            $('#multifeedOptions')
              .append($('<option></option>')
                .attr('value', feed.url)
                .text(feed.title));
          });
          $('#multifeed').show();
        }
      }
    })
  },

  applyUserSettings: function() {
    var newPass1 = $('#settingsPassword').val();
    var newPass2 = $('#settingsPasswordConf').val();
    var email = $('#settingsEmail').val();
    var currentPassword = $('#settingsCurrPassword').val();
    if (newPass1 != newPass2) {
      alert('Passwords do not match :( -- ' + newPass1 + ' vs ' + newPass2);
      return;
    }
    domain.applyUserSettings(email, newPass1, currentPassword);
  },

  initialize: function() {
    // Set up ajax loaders.
    $(document).ajaxStart(function() {
      $('.ajaxLoader').show();
      console.log('tried to show');
    }).ajaxStop(function() {
      $('.ajaxLoader').hide();
      console.log('tried to hide');
    });

    // Load label expansion.
    ui._expandedLabels = [];
    var labelObj = localStorage.expandedLabels;
    if (labelObj) {
      ui._expandedLabels = JSON.parse(labelObj).labels;
    }

    ui.resizeMainPanel();
    $(window).resize(ui.resizeMainPanel);
    view.initialize();

    // Some minor databinding stuff.
    $('#addFeedButton').click(view.showAddFeedWindow);
    $('#multifeedOptions').change(function() {
      $('#addFeedUrl').val($('#multifeedOptions').val());
    });
    $('#articleList .content').scroll(function() {
      ui.maybeLoadMoreArticles();
    });

    ui.setupKeybindings();
  },

  maybeLoadMoreArticles: function() {
    var articleList = $('#articleList .content');
    var top = articleList.scrollTop();
    var length = articleList.height();
    if (ui.currentFeed) {

    } else {
      // If we have a label selected, we need to stitch together a fake chunk from it
      // based on dates -- we want to ensure that we won't load more chunks and then
      // have new intermediate articles.
      console.log('bad command or filename');
    }
  },

  setupKeybindings: function() {
    var bindings = {
      'j': domain.nextArticle,
      'k': domain.previousArticle,
      'J': domain.nextFeed,
      'K': domain.previousFeed,
      'o': function() {
        var art = domain.currentArticle;
        if (!art) {
          return;
        }
        window.open(art.Link, '_blank');
      },
      'A': view.showAddFeedWindow,
      'u': domain.markUnread,
      'r': domain.markRead,
      'M': domain.markOlderRead
    };

    $(document).keypress(function(evt) {
      if (!ui.showingPopup) {
        $.each(bindings, function(key, fn) {
          if (evt.which == key.charCodeAt(0)) {
            fn();
          }
        });
      }
    });
  },

  isArticleVisible: function(artId) {
    var count = $('#' + util.articleId(artId) + ':visible').length;
    return count > 0;
  },

  fmtDate: function(date) {
    return date.toISOString().replace('T', ' ').substring(0, 16);
  },

  authors: function(article) {
    function formatAuthor(author) {
      return ui.template('authorLink', { author: author });
    }
    if (!article.Authors) {
      if (!feed.Authors) {
        return '';
      }
      return util.commaAnd(feed.Authors, formatAuthor);
    }
    return util.commaAnd(article.Authors, formatAuthor);
  },

  updateTitle: function() {
    var f = ui.currentFeed || ui.currentLabel || domain.allList;
    if (!f) {
      window.document.title = 'Pierce RSS Reader';
      return;
    }
    var unread = f.UnreadCount;
    var topic = f.title;
    if (unread) {
      window.document.title = topic + ' (' + unread + ') - Pierce RSS Reader';
    } else {
      window.document.title = topic + ' - Pierce RSS Reader';
    }
  },

  iconUrl: function(feed) {
    if (feed.IconUri) {
      return feed.IconUri;
    }
    return '/Content/no-icon.png';
  },

  logout: function() {
    document.cookie = "sessionToken=;expires=Thu, 01 Jan 1970 00:00:00 UTC; path=/;";
    window.location.refresh();
  },

  // this is so everything can end with a comma
  _barrier: null
};

var util = {
  hashString: function(str) {
    if (str == null) return 0;
    var hash = 0;
    for (var i = 0; i < str.length; i++) {
      hash = ((hash << 5) - hash) + str.charCodeAt(i);
      hash = hash & hash;
    }
    return Math.abs(hash);
  },

  commaAnd: function(list, fmt) {
    if (list.length == 0) return '';
    if (list.length == 1) {
      return fmt(list[0]);
    }
    if (list.length == 2) {
      return fmt(list[0]) + ' and ' + fmt(list[1]);
    }
    var str = fmt(list[0]);
    for (var i = 1; i < list.length - 1; i++) {
      str += ', ';
      str += fmt(list[i]);
    }
    str += ', and ' + fmt(list[list.length - 1]);
    return str;
  },

  articleId: function(article) {
    // Should probably scrub [^a-zA-Z_] from this...
    return 'articleli_' + article.id;
  },

  jsDate: function(aspNetDate) {
    return new Date(parseInt(aspNetDate.substr(6)));
  },

  sortArticles: function(articles) {
    if (!articles) return;
    var w = 0;
    for (var r = 0; r < articles.length; r++) {
      if (articles[r] != null) {
        articles[w] = articles[r];
        w++;
      }
    }
    articles.length = w;
    articles.sort(function(a, b) {
      return b.publishDate.getTime() - a.publishDate.getTime();
    })
  },

  sortFeeds: function(feeds) {
    feeds.sort(function(a, b) {
      return a.title.localeCompare(b.title);
    });
  },

  safeId: function(name) {
    return name.replace(/[^a-zA-Z]/, '') + util.hashString(name);
  },

  // this is so everything can end with a comma
  _barrier: null
};



console.log('inserting document-ready function');
$(document).ready(function() {
  console.log('readying UI');
  ui.initialize();
  console.log('readying domain');
  domain.initialize();

  console.log('checking cookies');
  if ($.cookie('sessionToken')) {
    console.log('have a user!');
    domain.refreshUser();
  } else {
    console.log('no user; trying to log in');
    view.showLoginWindow();
  }
});
