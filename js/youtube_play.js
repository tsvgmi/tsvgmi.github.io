/*
 * This script requires videos array to be setup externally
 */
var cur_player = null;
var players    = [];

function pe_toggle_chord(button) {
  var lyric_id = button.getAttribute('data-lyric-id');
  var note_id  = button.getAttribute('data-note-id');
  if (button.classList.contains('active')) {
    $('#' + lyric_id + ' .chord').show();
    $('#' + lyric_id + ' #' + note_id).show();
  } else {
    $('#' + lyric_id + ' .chord').hide();
    $('#' + lyric_id + ' #' + note_id).hide();
  }
}

function pe_playVideo(button) {
  var lyric_id = button.getAttribute('data-lyric-id');
  var main_id  = button.getAttribute('data-main-id');
  var vindex   = button.getAttribute('data-vindex');
  console.log('play video ' + vindex + ' + ' + lyric_id);

  console.log('vindex: ' + vindex);
  if (vindex >= 0) {
    players[vindex].playVideo();
  }
  $('.pl_collapse').collapse('hide');
  $('#' + lyric_id).collapse('show');
  $('#' + main_id)[0].scrollIntoView(true);
}

function pe_font(button, adjustment) {
  var lyric_id = button.getAttribute('data-lyric-id');
  t2lyric = $('#' + lyric_id + ' .t2lyric');
  cursize = t2lyric.css('font-size');
  newsize = parseFloat(cursize) * adjustment;
  console.log('cursize:' + cursize + ' newsize:' + newsize + ' adjustment:'+adjustment);
  t2lyric.css('font-size', newsize);
}

var FlatKeys = ['Dm', 'F', 'Bbm', 'Db', 'Cm', 'Eb', 'Ebm', 'Gb',
                'Fm', 'Ab', 'Gm', 'Bb'];
function pe_transpose(button, offset) {
  var lyric_id = button.getAttribute('data-lyric-id');
  var elem     = document.getElementById(lyric_id);
  var foptions = {};

  var check_flat = false
  $('#' + lyric_id + ' .chord').each(function(index) {
    ctext = $(this).html();
    new_chord = transpose_mkey(ctext, offset, foptions);

    // First time only
    if (!check_flat) {
      check_flat = true;
      // Need to strip out non chord modified.  Note this code
      // require the 1st chord in the piece have to be the scale
      new_scale = new_chord.match(/^[A-G][#b]?m?/);
      if ((new_scale != null) && (FlatKeys.indexOf(new_scale[0]) >= 0)) {
        foptions['flat'] =  true;
      }
      console.log('checking flat key for: '+new_chord + ' - it is:' + foptions['flat'] + ' new_scale: ' + new_scale);
    }

    $(this).html(new_chord);
  })
}

// Extract base key and mod (sharp/flat)
function split_key(key) {
  if ((key[1] == 'b') || (key[1] == '#')) {
    bkey = key.substr(0, 2);
    mod  = key.substr(2, key.length).trim();
  } else {
    bkey = key[0];
    mod  = key.substr(1, key.length).trim();
  }
  return {'base':bkey, 'mod':mod};
}


var KeyPos = ['A', 'A#|Bb', 'B', 'C', 'C#|Db', 'D',
              'D#|Eb', 'E', 'F', 'F#|Gb', 'G', 'G#|Ab'];
var PKeyPos = KeyPos.map(function(p) {
  return new RegExp('^' + p + '$')
});

// Transpose a single chord.  Notation is chord[/bass]
function transpose_mkey(keys, offset, options) {
  var output = [];
  var bkey, mod, bofs, tkey, tkeys;

  // Incase key is specified as chord/bass.  We transpose both
  //console.log('keys: '+keys + ' KeyPos: ' + KeyPos + ' options:'+options);
  keys.split('/').forEach(function(key) {
    kset = split_key(key)
    bofs = PKeyPos.findIndex(function(elem) {
      return kset['base'].match(elem);
    });
    // Order of key (0-11)
    //console.log('bofs:'+bofs);
    if (bofs >= 0) {
      // Calculate target key
      tkey  = KeyPos[(bofs+offset+12) % 12];
      //console.log('bofs:'+bofs+ ' offset:'+offset + ' tkey:'+tkey);
      tkeys = tkey.split('|');
      if (options['flat']) {
        output.push(tkeys[tkeys.length-1]+kset['mod']);
      } else {
        output.push(tkeys[0]+kset['mod']);
      }
    } else {
      console.log("Does not know how to transpose " + key);
      output.push(key);
    };
  });
  return output.join('/');
}

function stopAllExcept(videoId='') {
  var vid;
  var player;
  console.log('Stopall except: ' + videoId);
  for (var i = 0; i < players.length; i++) {
    player = players[i];
    if (videoId != '') {
      vid = player.getVideoData().video_id;
      if (vid != videoId) {
        if (player.getPlayerState() == 1) {
          console.log("Stop:" + videoId + " " + vid + " status:" + player.getPlayerState());
          player.stopVideo();
        }
      }
    } else {
      console.log('Stop here? ' + videoId);
      player.stopVideo();
    }
  }
}

function onYouTubeIframeAPIReady() {
  for (var i = 0; i < videos.length; i++) {
    var cur_video = videos[i];
    var avideo    = cur_video['video'];
    var vid       = cur_video['vid'];
    var start     = cur_video['start'];
    var end       = cur_video['end'];
    var player    = new YT.Player(vid, {
      height: '140',
      width:  '100%',
      playerVars: {"autoplay":0, "start":start, "end":end,
                   "origin":"https://www.youtube.com"},
      videoId: avideo,
      playsinline: true,
      events: {
        'onStateChange': function(event){
          var mplayer = event.target
          var mdata   = mplayer.b.b;
          if (event.data == 0) {
            start  = mdata['playerVars']['start'];
            console.log(mdata);
            console.log('Restarting ' + mdata['videoId'] + ' ' + start);
            mplayer.seekTo(start);
            cur_player = mplayer.playVideo();
          }
          if (event.data == 1) {
            console.log('Start ' + mdata['videoId'] + ' event: ' + event.data);
            stopAllExcept(mdata['videoId']);
          }
        }
      }
    });
    players.push(player);
  }
}
