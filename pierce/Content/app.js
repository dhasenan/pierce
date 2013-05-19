var user;

var domain = {
  // raw feeds (none of the tag-aggregated feeds)
  realFeeds: [],
  labels: [],

  /********* Read-only properties. ***********/
  getArticles: function() {
    if (ui.currentFeed) {
      return ui.currentFeed.Articles;
    } else if (ui.currentLabel) {
      return ui.currentLabel.Articles;
    } else {
      return [];
    }
  },

  getSubscription: function(feedId) {
    if (!user.Subscriptions) return;
    for (var i = 0; i < user.Subscriptions.length; i++) {
      if (user.Subscriptions[i].FeedId == feedId) {
        return user.Subscriptions[i];
      }
    }
    return null;
  },

  getFeed: function(feedId) {
    if (!domain.feeds) {
      return null;
    }
    for (var i = 0; i < domain.feeds.length; i++) {
      if (domain.feeds[i].Id == feedId) {
        return domain.feeds[i];
      }
    }
    return null;
  },

  getArticle: function(feed, artId) {
    for (var i = 0; i < feed.Articles.length; i++) {
      if (feed.Articles[i].Id == artId) {
        return feed.Articles[i];
      }
    }
    return null;
  },

  // Get a label object based on the label name (eg 'Yogscast' -> {Title: 'Yogscast', ...})
  getLabel: function(labelId) {
    for (var i = 0; i < domain.labels.length; i++) {
      if (domain.labels[i].Id == labelId) {
        return domain.labels[i];
      }
    }
    return null;
  },

  // Get the number of unread articles in the given feed or label.
  unreadCount: function(feed) {
    var articles = feed.Articles;
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
    var lab = {};
    var unlisted = [];
    $.each(domain.realFeeds, function(i, feed) {
      var sub = domain.getSubscription(feed.Id);
      var labels = sub ? sub.Labels : [];
      if (labels.length) {
        $.each(labels, function(j, name) {
          var e = lab[name];
          if (e) {
            e.Feeds.push(feed);
          } else {
            lab[name] = {
              Title: name,
              Id: 'label_' + util.safeId(name),
              Feeds: [feed]
            };
          }
        });
      } else {
        unlisted.push(feed);
      }
    });

    var lablist = [];
    $.each(lab, function(k, label) {
      lablist.push(label);
    });

    domain.allList = {
      Title: 'All',
      Id: 'special_label_All',
      Feeds: domain.realFeeds
    };
    lablist.sort(function(a, b) {
      if (a.Title < b.Title) return -1;
      if (a.Title > b.Title) return 1;
      return 0;
    });
    lablist = [domain.allList].concat(lablist);
    domain.updateLabelUnreadCounts(lablist);

    domain.uncategorizedList = {
      Title: 'Uncategorized',
      Id: 'special_label_Uncategorized',
      Feeds: unlisted
    };
    lablist.push(domain.uncategorizedList);
    $.each(lablist, function(k, label) {
      util.sortFeeds(label.Feeds);
      label.Articles = domain.buildCombinedArticles(label.Feeds);
    });

    domain.labels = lablist;
    ui.displayFeeds();
  },

  buildCombinedArticles: function(feeds) {
    var combined = [];
    for (var i = 0; i < feeds.length; i++) {
      combined = combined.concat(feeds[i].Articles);
    }
    util.sortArticles(combined);
    return combined;
  },

  /*********** Updating, or munging input. *************/
  mungeFeed: function(feed) {
    feed.LastRead = util.jsDate(feed.LastRead);
    feed.NextRead = util.jsDate(feed.NextRead);
    feed.ReadInterval = feed.ReadInterval.TotalSeconds;
    feed.Autogenerated = false;
    var sub = domain.getSubscription(feed.Id);
    feed.Chunks = [];
    $.each(feed.ChunkIds, function(i, id) {
      feed.Chunks.push({Id: id, Loaded: false, Articles: []});
    });
    if (feed.Articles) {
      $.each(feed.Articles, function(i, art) {
        art.Feed = feed;
        art.PublishDate = util.jsDate(art.PublishDate);
        if (sub) {
          art.IsRead = sub.ReadArticles.indexOf(art.Id) >= 0;
        }
        for (var j = 0; j < feed.Chunks.length; j++) {
          if (feed.Chunks[j].Id == art.ChunkId) {
            feed.Chunks[j].Articles.push(art);
          }
        }
      });
      util.sortArticles(feed.Articles);
    }
    feed.UnreadCount = domain.unreadCount(feed);
    if (sub && sub.Title) {
      feed.Title = sub.Title;
    }
    // This probably shouldn't be here...
    ui.updateTitle();
  },

  refreshUser: function() {
    $.ajax('/Users/Get', {
      dataType: 'json',
      success: function(data, statusText, xhr) {
        user = data;
        for (var i = 0; i < user.Subscriptions.length; i++) {
          var sub = user.Subscriptions[i];
          sub.CheckInterval = sub.CheckInterval.TotalSeconds;
        }
        ui.updateUserInfos();
        domain.refreshFeeds();
      },
      error: function() {
        view.showLoginWindow();
      }
    });
  },

  refreshFeeds: function() {
    var updatesPending = 0;
    var feeds = [];
    $.each(user.Subscriptions, function(i, sub) {
      feeds.push(null);
      var existing = domain.getFeed(sub.FeedId);
      var lastRead = existing ? existing.LastRead.toISOString() : null;
      updatesPending++;
      $.ajax('/Feeds/Get', {
        data: {
          'id': sub.FeedId,
          'lastRead': lastRead
        },
        success: function(data) {
          feeds[i] = data['Feed'];
          if (data['UpToDate']) {
            // already munged
            feeds[i] = existing;
            return;
          }
          domain.mungeFeed(feeds[i]);
          updatesPending--;
          if (updatesPending <= 0) {
            domain.realFeeds = feeds;
            domain.reloadFeedInfo();
          }
        }
      });
    });
  },

  refreshFeed: function(feedId) {
    $.ajax('/Feeds/RefreshNow', {
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
    if (ui.currentFeed)
      ui.showFeed(ui.currentFeed.Id);
    ui.updateTitle();
  },

  /********* Modifying data ************/
  updateFeed: function(feed) {
    domain.mungeFeed(feed);
    for (var i = 0; i < domain.realFeeds.length; i++) {
      if (domain.realFeeds[i].Id == feed.Id) {
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
    $.each(labels, function(i, label) {
      var unread = 0;
      $.each(label.Feeds, function(j, feed) {
        unread += feed.UnreadCount;
      });
      label.UnreadCount = unread;
    })
  },

  markRead: function(article) {
    article.IsRead = true;
    article.Feed.UnreadCount--;
    domain.updateLabelUnreadCounts(domain.labels);
    domain.getSubscription(article.Feed.Id).ReadArticles.push(article.Id);
    $.ajax('/Feeds/MarkRead', {
      dataType: 'json',
      data: {
        feedId: article.Feed.Id,
        articleId: article.Id
      }
    });

    // 'article.Feed' is always the unique 'natural' feed that we got the
    // article from, whereas 'feed' might be all feeds, or a label...
    ui.updateFeedDisplay(article.Feed);

    // Also update all autogenerated stuff, since that should be quick
    // for small numbers of feeds and we aren't currently sure what
    // autogenerated feeds contain this article.
    for (var i = 0; i < domain.feeds.length; i++) {
      var f = domain.feeds[i];
      if (f.Autogenerated) {
        ui.updateFeedDisplay(f);
      }
    }

    ui.updateTitle();
  },

  modifyFeed: function(feedId, title, checkInterval, labels) {
    $.ajax('/Feeds/Update', {
      data: {
        id: feedId,
    title: title,
    checkIntervalSeconds: checkInterval * 60,
    labels: labels
      },
    success: function(res, foo, bar) {
      feed = domain.getFeed(feedId);
      sub = domain.getSubscription(feedId);
      sub.Title = res.Subscription.Title;
      sub.CheckInterval = res.Subscription.CheckInterval.TotalSeconds;
      feed.ReadInterval = res.Feed.ReadInterval.TotalSeconds;
      if (labels) sub.Labels = labels.split(',');
      if (sub.Title) feed.Title = sub.Title;
      view.closeModifyFeedWindow();
      domain.buildLabels();
      ui.displayFeeds();
    }
    });
  },

  unsubscribe: function(feedId) {
    $.ajax('/Feeds/Unsubscribe', {
      data: { id: feedId },
    success: function() {
      alert('Successfully unsubscribed.');
      view.closeModifyFeedWindow();
      domain.removeFeed(feedId);
      ui.displayFeeds();
    }
    });
  },

  applyUserSettings: function(email, newPassword, currentPassword) {
    $.ajax('/Users/Update', {
      data: {
        email: email,
        currentPassword: currentPassword,
        newPassword: newPassword
      },
      success: function(data) {
        if (data['Error']) {
          alert(data['Error']);
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
    if (!f.Articles) {
      domain._moveFeed(offset);
      return;
    }
    var articleIndex = null;
    var currentArticle = domain.currentArticle;
    if (currentArticle) {
      for (var i = 0; i < f.Articles.length; i++) {
        if (f.Articles[i].Id == currentArticle.Id) {
          articleIndex = i;
          break;
        }
      }
      if (articleIndex === null) {
        // No, really, what the hell?
        domain._moveFeed(offset);
        return;
      }
      var index = articleIndex + offset;
      while (true) {
        if (index < 0 || index >= f.Articles.length) {
          domain._moveFeed(offset);
          return;
        }
        if (!ui.isArticleVisible(f.Articles[index])) {
          index += offset;
          continue;
        }
        ui.showArticle(f, f.Articles[index].Id);
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
        if (label.Feeds[i].Id == currentFeed.Id) {
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
      ui.showFeed(f.Id, label.Id);
      var ai = (offset < 0) ? f.Articles.length - 1 : 0;
      while (ai >= 0
          && ai < f.Articles.length
          && (f.Articles[ai].IsRead || !ui.showingUnreadOnly)) {
        ai += offset;
      }
      var art = f.Articles[ai];
      if (art) {
        ui.showArticle(f, f.Articles[ai].Id);
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
    var curr = ui.currentLabel.Id;
    for (var i = 0; i < domain.labels.length; i++) {
      if (curr == domain.labels[i].Id) {
        console.log('starting label ' + i);
        var k = i + offset;
        while (k >= 0 && k < domain.labels.length && !domain.labels[k].Articles) {
          console.log('skipping label ' + k);
          k += offset;
        }
        if (k < 0 || k >= domain.labels.length) {
          console.log('got too far; quitting');
          return;
        }
        var label = domain.labels[k];
        ui.showLabel(label.Id);
        if (!ui.isExpanded(label.Id)) {
          ui.toggleExpanded(label.Id);
        }
        if (moveFeed) {
          console.log('okay, moving feed');
          domain._moveFeed(offset, true);
        }
        return;
      }
    }
    console.log('YOLO');
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

    // Every 5 minutes
    window.setInterval(domain.refreshUser, 5 * 60 * 1000);
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
      console.log('expanded ' + labelId);
    }
    localStorage.expandedLabels = JSON.stringify({ labels: ui._expandedLabels });
  },

  closeFeedPopup: function() {
    view.closeFeedWindow();
  },

  template: function(name, data) {
    var templ = $('script#' + name);
    if (!templ) {
      console.log('template ' + name + ' not found!');
      return 'TEMPLATE ' + name + ' NOT FOUND';
    }

    // Have to trim template text in order not to give jquery a hissy fit.
    return _.template(templ.text(), data)
      .replace(/^\s+/g, '')
      .replace(/\s+$/g, '');
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
    $('.feedli_' + feed.Id).replaceWith(ui.template('feedli', {feed: feed}));
  },

  showingUnreadOnly: false,
  currentFeed: null,

  showLabel: function(labelId) {
    var label = domain.getLabel(labelId);
    if (!label) return;
    ui.currentFeed = null;
    ui.currentLabel = label;
    ui.showArticles(domain.buildCombinedArticles(label.Feeds));
    ui.selected('#labelName_' + labelId);
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
      labelId = ui.currentLabel.Id;
    }
    var feed = domain.getFeed(feedId);
    if (!feed) return;
    ui.currentFeed = feed;
    ui.currentLabel = domain.getLabel(labelId);
    if (feed.Articles)
      ui.showArticles(feed.Articles);
    ui.selected('.lf_' + feedId + labelId);
  },

  showArticles: function(articles) {
    $('.listRow').removeClass('selectedItem');
    $('#articleList .content').empty();
    // TODO this should be a template
    $.each(articles, function(i, article) {
      if (ui.showingUnreadOnly && article.IsRead) {
        return;
      }
      var dom = ui.template('articleli', {
        article: article,
      });
      $('#articleList .content').append(dom);
    });
    ui.updateTitle();
  },

  showArticle: function(o, artId) {
    var feed = null;
    if (o.Articles) {
      feed = o;
    } else {
      feed = domain.getFeed(o) || domain.getLabel(o);
    }
    var article = domain.getArticle(feed, artId);
    if (!article) {
      console.log('feed ' + feedId + ' has no article ' + artId);
      return;
    }
    $('.articleli').removeClass('selectedItem');
    var artDiv = $('#' + util.articleId(article));
    artDiv.addClass('selectedItem');
    artDiv.removeClass('unread');
    artDiv.addClass('read');

    // pos: position *relative to scrolled viewport*
    var pos = artDiv.position();
    var par = artDiv.parent();
    var margin = 2;
    if (pos.top < margin) {
      var alreadyHidden = par.scrollTop();
      // we're hiding 300px
      // relative to hidden, item is at -50
      // need to scroll to 250 hidden, and a bit further up for margin
      par.scrollTop(par.scrollTop() + pos.top - margin);
    } else if (pos.top > par.height()) {
      // now we want the entry as the last thing there
      // that means we hide fewer pixels -- par.height() fewer means our entry is the first thing
      // below the fold, so we raise it up by one artDiv height
      par.scrollTop(par.scrollTop() - par.height() + pos.top - margin + artDiv.height());
    }

    $('#articleView .content').html(ui.template('articlefull', {
      feed: article.Feed,
      article: article
    }));

    $('#articleTitle').text(article.Feed.Title);
    domain.showingArticle(article);
    ui.updateTitle();
    $('#articleContent').focus().scrollTop(0);
  },

  toggleUnreadOnly: function() {
    if (ui.showingUnreadOnly) {
      ui.showingUnreadOnly = false;
      $('#toggleUnread').text('Unread');
      $('.read').show();
    } else {
      ui.showingUnreadOnly = true;
      $('#toggleUnread').text('All');
      $('.read:not(.selectedItem)').hide();
    }
    if (ui.currentFeed) {
      ui.showFeed(ui.currentFeed.Id);
    }
  },

  addFeed: function() {
    var url = $('#addFeedUrl').val();
    var title = $('#addFeedTitle').val();
    var labelString = $('#addFeedLabels').val();
    $.ajax('/Feeds/Add', {
      dataType: 'json',
      data: {
        url: url,
        title: title,
        labels: labelString
      },
      success: function(data, statusText, xhr) {
        if (!data['FoundFeeds']) {
          // leave window open for corrections
          alert('I didn\'t find any feeds :(');
        } else if (data['AddedFeed']) {
          // mungeFeed requires an existing subscription. Deal with it first.
          var sub = data['Subscription'];
          if (sub) {
            sub.CheckInterval = sub.CheckInterval.TotalSeconds;
            user.Subscriptions.push(sub);
          }
          var added = data['AddedFeed'];
          ui.closeFeedPopup();
          if (domain.getFeed(added.Id)) return;
          domain.mungeFeed(added);
          domain.realFeeds.push(added);
          domain.reloadFeedInfo();
          ui.displayFeeds();
        } else {
          $('#multifeedOptions').empty();
          $('#addFeedUrl').val(data['DiscoveredFeeds'][0].Uri);
          $.each(data['DiscoveredFeeds'], function(i, feed) {
            $('#multifeedOptions')
              .append($('<option></option>')
                .attr('value', feed.Uri)
                .text(feed.Title));
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
    var topic = f.Title;
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
    return 'articleli_' + article.Id;
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
      return b.PublishDate.getTime() - a.PublishDate.getTime();
    })
  },

  sortFeeds: function(feeds) {
    feeds.sort(function(a, b) {
      return a.Title.localeCompare(b.Title);
    });
  },

  safeId: function(name) {
    return name.replace(/[^a-zA-Z]/, '') + util.hashString(name);
  },

  // this is so everything can end with a comma
  _barrier: null
};



$(document).ready(function() {
  ui.initialize();
  domain.initialize();

  // TODO should be something else, no?
  if ($.cookie('.MONOAUTH')) {
    domain.refreshUser();
  } else {
    view.showLoginWindow();
  }
});
