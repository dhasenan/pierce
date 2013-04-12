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
    if (feed.Articles) {
      $.each(feed.Articles, function(i, art) {
        art.Feed = feed;
        art.PublishDate = util.jsDate(art.PublishDate);
        if (sub) {
          art.IsRead = sub.ReadArticles.indexOf(art.Id) >= 0;
        }
      });
      util.sortArticles(feed.Articles);
    }
    if (sub && sub.Title) {
      feed.Title = sub.Title;
    }
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
        ui.showLoginWindow();
      }
    });
  },

  refreshFeeds: function() {
    $.ajax('/Feeds/List', {
      dataType: 'json',
      success: function(data, statusText, xhr) {
        var updatesPending = 0;
        var feeds = data['Feeds'];
        // We just got the new canonical list of feeds.
        // We're going to replace our existing list.
        // But the new stuff doesn't include the article lists for any of these.
        // We'll determine which ones might have updated since last time and
        // reload them from the source. For the remainder, we'll just copy the
        // articles from what we already have.
        $.each(feeds, function(i, feed) {
          domain.mungeFeed(feed);
          // This is O(n**2) because I'm lazy.
          var existing = domain.getFeed(feed.Id);
          if (existing && existing.LastRead == feed.LastRead) {
            feed.Articles = existing.Articles;
          } else {
            updatesPending++;
            $.ajax('/Feeds/Get', {
              data: {
                'id': feed.Id
              },
              success: function(data) {
                feeds[i] = data['Feed'];
                domain.mungeFeed(feeds[i]);
                updatesPending--;
                if (updatesPending <= 0) {
                  domain.realFeeds = feeds;
                  domain.reloadFeedInfo();
                }
              }
            });
          }
        });
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

  markRead: function(article) {
    article.IsRead = true;
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
        ui.showArticle(f, f.Articles[0].Id);
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

  _moveFeed: function(offset, startFeed) {
    var currentFeed = ui.currentFeed;
    if (!currentFeed) {
      domain._moveLabel(offset);
      return;
    }
    // We *need* to track what label we're in. This is going to go in a strange order.
    for (var i = 0; i < domain.feeds.length; i++) {
      if (domain.feeds[i].Id == currentFeed.Id) {
        var index = i + offset;
        if (index < 0 || index >= domain.feeds.length) {
          domain._moveLabel(offset);
          return;
        } else {
          var f = domain.feeds[index];
          ui.showFeed(f.Id);
          if (f.Articles.length) {
            var ai = (offset < 0) ? f.Articles.length - 1 : 0;
            while (ai >= 0
                && ai < f.Articles.length
                && !ui.isArticleVisible(f.Articles[ai])) {
              ai += offset;
            }
            ui.showArticle(f, f.Articles[ai].Id);
          } else {
          }
        }
        return;
      }
    }
    domain._moveLabel(offset);
  },

  _moveLabel: function(offset) {
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
    } 
    ui.displayFeeds();
    ui.updateTitle();
  },
  
  initialize: function() {

    // Every 5 minutes
    window.setInterval(domain.refreshUser, 5 * 60 * 1000);
  }
};

var ui = {
  _expandedLabels: [],
  bodyLayout: null,

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
  },

  closeFeedPopup: function() {
    $('#addFeedWindow').dialog('close');
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
    $('#modFeedUrl').val(feed.Uri);
    $('#modFeedTitle').val(feed.Title);
    $('#modFeedInterval').val((sub.CheckInterval / 60) | 0);
    if (sub.Labels) {
      $('#modFeedLabels').val(sub.Labels.join(', '));
    }
    ui.showingPopup = true;
    $('#modifyFeedWindow').dialog({
      close: function() { ui.showingPopup = false; },
      height: 'auto',
      width: 'auto',
      buttons: [
        {
          text: 'Save',
          click: function() {
            var title = $('#modFeedTitle').val();
            var checkInterval = $('#modFeedInterval').val();
            var labels = $('#modFeedLabels').val();
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
                $('#modifyFeedWindow').dialog('close');
                domain.buildLabels();
                ui.displayFeeds();
              }
            });
          }
        },
        {
          text: 'Unsubscribe',
          click: function() {
            var reallyUnsubscribe = confirm(
                'Are you sure you want to unsubscribe from ' + feed.Title + '?');
            if (reallyUnsubscribe) {
              $.ajax('/Feeds/Unsubscribe', {
                data: { id: feedId },
                success: function() {
                  alert('Successfully unsubscribed.');
                  $('#modifyFeedWindow').dialog('close');
                  domain.removeFeed(feedId);
                  ui.displayFeeds();
                }
              });
            } else {
              $('#modifyFeedWindow').dialog('close');
            }
          }
        },
        {
          text: 'Refresh',
          click: function() {
            $.ajax('/Feeds/RefreshNow', {
              data: {
                id: feedId
              },
              success: function(data, a, b) {
                domain.updateFeed(data);
              }
            })
            $('#modifyFeedWindow').dialog('close');
          }
        },
      ]
    });
  },

  showLoginWindow: function() {
    ui.showingPopup = true;
    $('#loginWindow').dialog({
      close: function() { ui.showingPopup = false; },
      height: 'auto',
      width: 'auto',
      buttons: [
        {
          text: 'Log in',
          click: function() {
            $.ajax('/Users/Login', {
              dataType: 'json',
              data: {
                'email': $('#email').val(),
                'password': $('#password').val(),
              },
              success: function(data, statusText, xhr) {
                ui.hideLoginWindow();
                user = data;
                ui.updateUserInfos();
                domain.refreshFeeds();
              }
            });
          }
        },
        {
          text: 'Register',
          click: function() {
            $.ajax('/Users/Register', {
              dataType: 'json',
              data: {
                'email': $('#email').val(),
                'password': $('#password').val(),
              },
              success: function(data, statusText, xhr) {
                ui.hideLoginWindow();
                user = data;
                ui.updateUserInfos();
                domain.refreshFeeds();
              }
            });
          }
        },
      ]
    });
  },

  hideLoginWindow: function() {
    $('#loginWindow').dialog('close');
  },

  displayFeeds: function() {
    if (!ui.currentFeed && !ui.currentLabel) {
      ui.currentLabel = domain.allLabel;
    }
    $('.feedList .content').html(ui.template('labelListTemplate', {labels: domain.labels}));
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
    console.log('selecting ' + query);
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
    ui.currentLabel = null;
    if (feed.Articles)
      ui.showArticles(feed.Articles);
    ui.selected('#labelContent_' + labelId + ' .feedli_' + feedId);
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
      $('.read').hide();
    }
    ui.showFeed(ui.currentFeed.Id);
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
          domain.mungeFeed(added);
          $.each(added.Articles, function(i, art) {
            console.log(typeof art.PublishDate);
          });
          domain.realFeeds.push(added);
          domain.reloadFeedInfo();
          ui.displayFeeds();
          ui.closeFeedPopup();
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

  showSettingsWindow: function() {
    ui.showingPopup = true;
    $('#settingsEmail').val(user.Email);
    $('#settingsCurrPassword').val('');
    $('#settingsPassword').val('');
    $('#settingsPasswordConf').val('');
    $('#settingsWindow').dialog({
      close: function() { ui.showingPopup = false; },
      height: 'auto',
      width: 'auto',
      buttons: [
        {
          text: 'Okay go!',
          click: function() {
            var newPass1 = $('#settingsPassword').val();
            var newPass2 = $('#settingsPasswordConf').val();
            if (newPass1 != newPass2) {
              alert('Passwords do not match :( -- ' + newPass1 + ' vs ' + newPass2);
              return;
            }
            $.ajax('/Users/Update', {
              data: {
                email: $('#settingsEmail').val(),
                currentPassword: $('#settingsCurrPassword').val(),
                newPassword: $('#settingsPassword').val()
              },
              success: function(data) {
                if (data['Error']) {
                  alert(data['Error']);
                } else {
                  $('#settingsWindow').dialog('close');
                }
              }
            });
          }
        },
      ]
    });
  },

  showAddFeedWindow: function() {
    $('#multifeed').hide();
    $('#addFeedUrl').val('');
    $('#addFeedTitle').val('');
    $('#addFeedLabels').val('');
    ui.showingPopup = true;
    $('#addFeedWindow').dialog({
      close: function() { ui.showingPopup = false; },
      height: 'auto',
      width: 'auto',
      buttons: [
        { text: 'Add feed!', click: ui.addFeed },
      ]
    });
  },

  initialize: function() {
    $.layout.defaults.stateManagement = {
      enabled: true,
      autoSave: true,
      autoLoad: true,
      stateKeys: 'north.size,south.size,east.size,west.size,',
      cookie: {
        expires: 365
      }
    };
    ui.resizeMainPanel();
    $(window).resize(ui.resizeMainPanel);
    // This is currently using the jquery ui layout plugin.
    // I have some annoyances with it. Consider switching to something better,
    // or at least simpler, like http://www.methvin.com/splitter/
    ui.bodyLayout = $('#mainPanel').layout({
      defaults: {
        applyDefaultStyles: true,
        resizable: true,
        closable: false,
        slidable: true,
        contentSelector: '.content',
        spacing_open: 4,
        spacing_closed: 4
      },
      south: {
        paneSelector: '.articleView',
        size: 400,
      },
      west: {
        paneSelector: '.feedList'
      },
      center: {
        paneSelector: '.articleList'
      }
    });

    $('#addFeedButton').click(ui.showAddFeedWindow);
    $('#multifeedOptions').change(function() {
      $('#addFeedUrl').val($('#multifeedOptions').val());
    });
    ui.setupKeybindings();
    ui.showingPopup = false;
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
      'A': ui.showAddFeedWindow,
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
    var unread = domain.unreadCount(f);
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
    ui.showLoginWindow();
  }
});
