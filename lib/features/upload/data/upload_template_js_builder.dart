import 'dart:convert';

import 'package:FANotifier/features/upload/domain/submission_template.dart';

String buildReadSubmissionTemplateFieldsScript() {
  return '''
        (function() {
          function __b64(o) { return 'B64:' + btoa(unescape(encodeURIComponent(JSON.stringify(o)))); }
          try {
            var form = document.getElementById('myform');
            if (!form) {
              return __b64({ ok: false, error: 'Finalize form not found. Make sure you are on the finalize page.' });
            }

            function selectObj(sel) {
              if (!sel) return null;
              var idx = sel.selectedIndex;
              var label = '';
              if (idx >= 0 && sel.options && sel.options[idx]) label = (sel.options[idx].text || '').trim();
              return { value: String(sel.value || ''), label: label || String(sel.value || '') };
            }

            var catSel = document.querySelector('select[name="cat"]');
            var atypeSel = document.querySelector('select[name="atype"]');
            var speciesSel = document.querySelector('select[name="species"]');

            var titleEl = document.querySelector('input#title');
            var msgEl = document.querySelector('textarea#message');
            var kwEl = document.getElementById('keywords');

            var folderNameEl = document.querySelector('input[name="create_folder_name"]');

            var selectedFolders = [];
            try {
              var checked = document.querySelectorAll('input[name="folder_ids[]"]:checked');
              for (var i = 0; i < checked.length; i++) {
                var cb = checked[i];
                var idAttr = cb.getAttribute('id') || '';
                var labelText = '';
                if (idAttr) {
                  var lbl = document.querySelector('label[for="' + idAttr + '"]');
                  if (lbl) labelText = (lbl.textContent || '').trim();
                }
                if (!labelText) {
                  var wrap = cb.closest('.folder_name');
                  if (wrap) {
                    var lbl2 = wrap.querySelector('label');
                    if (lbl2) labelText = (lbl2.textContent || '').trim();
                  }
                }
                selectedFolders.push({
                  value: String(cb.value || ''),
                  label: labelText || String(cb.value || '')
                });
              }
            } catch (_) {}

            var rEl = document.querySelector('#myform input[name="rating"]:checked');
            var ratingObj = null;
            if (rEl) {
              var lblr = '';
              var labelEl = rEl.closest('label');
              if (labelEl) lblr = (labelEl.textContent || '').trim();
              if (!lblr && rEl.id) {
                var forLbl = document.querySelector('label[for="' + rEl.id + '"]');
                if (forLbl) lblr = (forLbl.textContent || '').trim();
              }
              ratingObj = { value: String(rEl.value || ''), label: lblr || String(rEl.value || '') };
            }

            var out = {
              category: selectObj(catSel),
              theme: selectObj(atypeSel),
              species: selectObj(speciesSel),
              rating: ratingObj,
              title: titleEl ? String(titleEl.value || '') : null,
              description: msgEl ? String(msgEl.value || '') : null,
              keywords: kwEl ? String(kwEl.value || '') : null,
              folderName: folderNameEl ? String(folderNameEl.value || '') : null,
              folders: selectedFolders
            };

            return __b64({ ok: true, fields: out });
          } catch (e) {
            return __b64({ ok: false, error: String(e) });
          }
        })();
      ''';
}

SubmissionTemplateFields? parseSubmissionTemplateFieldsFromJsMap(
  Map<String, dynamic> map,
) {
  final fields = map['fields'];
  if (fields is! Map<String, dynamic>) {
    return null;
  }

  final normalized = <String, dynamic>{
    'category': fields['category'],
    'theme': fields['theme'],
    'species': fields['species'],
    'rating': fields['rating'],
    'title': fields['title'],
    'description': fields['description'],
    'keywords': fields['keywords'],
    'folderName': fields['folderName'],
    'folders': fields['folders'],
  };

  return SubmissionTemplateFields.fromJson(normalized);
}

String buildApplySubmissionTemplateScript(SubmissionTemplateFields fields) {
  final fieldsJson = jsonEncode(fields.toJson());

  return '''
        (function() {
          function __b64(o) { return 'B64:' + btoa(unescape(encodeURIComponent(JSON.stringify(o)))); }

          function __escapeHTML(text) {
            var htmlEscapes = {
              '&': '&amp;',
              '<': '&lt;',
              '>': '&gt;',
              '"': '&quot;',
              "'": '&#x27;',
              '/': '&#x2F;'
            };
            return String(text).replace(/[&<>"'\\/]/g, function(match) { return htmlEscapes[match]; });
          }

          function __setHidden(el, hidden) {
            if (!el) return;
            try {
              if (hidden) el.classList.add('hidden');
              else el.classList.remove('hidden');
            } catch (_) {}
          }

          function __updateTitlePreview(value) {
            var defaultTitle = document.querySelector('.default-preview-title');
            var userTitle = document.querySelector('.user-preview-title');
            if (!defaultTitle || !userTitle) return;
            var v = String(value || '');
            if (v !== '') {
              __setHidden(defaultTitle, true);
              userTitle.textContent = v.replace(/\\n/g, ' ');
              __setHidden(userTitle, false);
            } else {
              __setHidden(defaultTitle, false);
              __setHidden(userTitle, true);
            }
          }

          function __updateDescPreview(value) {
            var defaultDesc = document.querySelector('.default-preview-text');
            var userDesc = document.querySelector('.user-preview-text');
            if (!defaultDesc || !userDesc) return;
            var v = String(value || '');
            if (v !== '') {
              __setHidden(defaultDesc, true);
              userDesc.innerHTML = __escapeHTML(v).replace(/\\n/g, '<br />');
              __setHidden(userDesc, false);
            } else {
              __setHidden(defaultDesc, false);
              __setHidden(userDesc, true);
              userDesc.innerHTML = '';
            }
          }

          function __syncPreviewToForm() {
            var titleEl = document.querySelector('input#title') || document.querySelector('input[name="title"]');
            var msgEl = document.querySelector('textarea#message');
            var titleVal = titleEl ? String(titleEl.value || '') : '';
            var msgVal = msgEl ? String(msgEl.value || '') : '';
            __updateTitlePreview(titleVal);
            __updateDescPreview(msgVal);
            return true;
          }

          try {
            var fields = $fieldsJson;
            var failed = [];

            function tryFind(selector) {
              try { return document.querySelector(selector); } catch (_) { return null; }
            }

            function setText(selector, value, label) {
              if (value === null || value === undefined) return;
              var el = tryFind(selector);
              if (!el) { failed.push(label); return; }
              el.value = String(value);
              el.dispatchEvent(new Event('input', { bubbles: true }));
              el.dispatchEvent(new Event('change', { bubbles: true }));
            }

            function setSelectByName(name, obj, label) {
              if (!obj || obj.value === null || obj.value === undefined) return;
              var el = tryFind('select[name="' + name + '"]');
              if (!el) { failed.push(label); return; }
              var v = String(obj.value);
              var ok = false;
              for (var i = 0; i < el.options.length; i++) {
                if (String(el.options[i].value) === v) { ok = true; break; }
              }
              if (!ok) { failed.push(label); return; }
              el.value = v;
              el.dispatchEvent(new Event('change', { bubbles: true }));
            }

            function setRating(obj, label) {
              if (!obj || obj.value === null || obj.value === undefined) return;
              var v = String(obj.value);
              var el = tryFind('#myform input[name="rating"][value="' + v + '"]');
              if (!el) { failed.push(label); return; }
              el.checked = true;
              el.dispatchEvent(new Event('change', { bubbles: true }));
            }

            function setFolders(list, label) {
              if (!Array.isArray(list)) return;
              try {
                var all = document.querySelectorAll('input[name="folder_ids[]"]');
                for (var i = 0; i < all.length; i++) {
                  all[i].checked = false;
                  all[i].dispatchEvent(new Event('change', { bubbles: true }));
                }

                for (var j = 0; j < list.length; j++) {
                  var obj = list[j];
                  if (!obj || obj.value === null || obj.value === undefined) continue;
                  var v = String(obj.value);
                  var cb = tryFind('input[name="folder_ids[]"][value="' + v + '"]');
                  if (!cb) { failed.push(label); continue; }
                  cb.checked = true;
                  cb.dispatchEvent(new Event('change', { bubbles: true }));
                }
              } catch (_) {
                failed.push(label);
              }
            }

            var form = document.getElementById('myform');
            if (!form) {
              return __b64({ ok: false, failed: ['Finalize form'] });
            }

            setSelectByName('cat', fields.category, 'Category');
            setSelectByName('atype', fields.theme, 'Theme');
            setSelectByName('species', fields.species, 'Species');
            setRating(fields.rating, 'Maturity Rating');

            setText('input#title', fields.title, 'Title');
            setText('textarea#message', fields.description, 'Description');
            setText('#keywords', fields.keywords, 'Keywords');

            setText('input[name="create_folder_name"]', fields.folderName, 'Folder Name');
            setFolders(fields.folders, 'Folder Name');

            __syncPreviewToForm();
            return __b64({ ok: true, failed: failed });
          } catch (e) {
            return __b64({ ok: false, failed: ['Unknown error'] });
          }
        })();
      ''';
}
