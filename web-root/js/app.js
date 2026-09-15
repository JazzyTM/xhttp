/* ============================================
   AniManga Hub — Main Application Script
   All 8 pages reference: js/app.js
   ============================================ */

document.addEventListener('DOMContentLoaded', function() {
  'use strict';

  // ==========================================
  // 1. THEME TOGGLE (Dark / Light)
  // ==========================================
  (function initThemeToggle() {
    var themeToggle = document.querySelector('.theme-toggle');
    var body = document.body;
    var docEl = document.documentElement;

    function applyTheme(theme) {
      if (theme === 'light') {
        body.classList.add('light-theme');
        if (themeToggle) {
          themeToggle.textContent = '\u2600\uFE0F';
          themeToggle.setAttribute('aria-label', 'Vkluchit tyomnu temu');
        }
        docEl.style.setProperty('--color-bg-primary', '#f8fafc');
        docEl.style.setProperty('--color-bg-secondary', '#ffffff');
        docEl.style.setProperty('--color-bg-card', '#ffffff');
        docEl.style.setProperty('--color-bg-card-hover', '#f1f5f9');
        docEl.style.setProperty('--color-text-primary', '#0f172a');
        docEl.style.setProperty('--color-text-secondary', '#475569');
        docEl.style.setProperty('--color-text-muted', '#64748b');
        docEl.style.setProperty('--color-border', '#e2e8f0');
        docEl.style.setProperty('--header-bg', 'rgba(248, 250, 252, 0.95)');
      } else {
        body.classList.remove('light-theme');
        if (themeToggle) {
          themeToggle.textContent = '\uD83C\uDF19';
          themeToggle.setAttribute('aria-label', 'Vkluchit svetlu temu');
        }
        docEl.style.setProperty('--color-bg-primary', '#0b1120');
        docEl.style.setProperty('--color-bg-secondary', '#111827');
        docEl.style.setProperty('--color-bg-card', '#1e293b');
        docEl.style.setProperty('--color-bg-card-hover', '#263449');
        docEl.style.setProperty('--color-text-primary', '#f1f5f9');
        docEl.style.setProperty('--color-text-secondary', '#94a3b8');
        docEl.style.setProperty('--color-text-muted', '#64748b');
        docEl.style.setProperty('--color-border', '#334155');
        docEl.style.setProperty('--header-bg', 'rgba(11, 17, 32, 0.95)');
      }
    }

    function getPreferredTheme() {
      var saved = localStorage.getItem('theme');
      if (saved === 'light' || saved === 'dark') {
        return saved;
      }
      if (window.matchMedia && window.matchMedia('(prefers-color-scheme: light)').matches) {
        return 'light';
      }
      return 'dark';
    }

    var initialTheme = getPreferredTheme();
    applyTheme(initialTheme);

    if (themeToggle) {
      themeToggle.addEventListener('click', function() {
        var currentTheme = body.classList.contains('light-theme') ? 'light' : 'dark';
        var newTheme = currentTheme === 'light' ? 'dark' : 'light';
        localStorage.setItem('theme', newTheme);
        applyTheme(newTheme);
        var event = new CustomEvent('themechange', { detail: { theme: newTheme } });
        document.dispatchEvent(event);
      });
    }

    if (window.matchMedia) {
      var mediaQuery = window.matchMedia('(prefers-color-scheme: light)');
      if (mediaQuery.addEventListener) {
        mediaQuery.addEventListener('change', function(e) {
          if (!localStorage.getItem('theme')) {
            applyTheme(e.matches ? 'light' : 'dark');
          }
        });
      }
    }
  })();

  // ==========================================
  // 2. KEYBOARD SHORTCUT: CMD/CTRL + K -> Search Focus
  // ==========================================
  (function initSearchShortcut() {
    var searchInput = document.querySelector('.search-input');
    if (!searchInput) return;

    document.addEventListener('keydown', function(e) {
      var isMac = navigator.platform.toUpperCase().indexOf('MAC') >= 0;
      var modifier = isMac ? e.metaKey : e.ctrlKey;
      if (modifier && (e.key === 'k' || e.key === 'K')) {
        e.preventDefault();
        searchInput.focus();
        searchInput.select();
        if (searchInput.scrollIntoView) {
          searchInput.scrollIntoView({ behavior: 'smooth', block: 'center' });
        }
      }
      if (e.key === 'Escape' && document.activeElement === searchInput) {
        searchInput.blur();
      }
    });
  })();

  // ==========================================
  // 3. HERO SLIDER - Auto-rotate every 8 seconds
  // ==========================================
  (function initHeroSlider() {
    var heroCards = document.querySelectorAll('.hero-card');
    if (!heroCards || heroCards.length <= 1) return;

    var currentIndex = 0;
    var sliderInterval = null;
    var HERO_INTERVAL = 8000;

    for (var i = 0; i < heroCards.length; i++) {
      if (heroCards[i].classList.contains('active')) {
        currentIndex = i;
        break;
      }
    }

    var sliderControls = document.querySelector('.hero-slider-controls');
    if (sliderControls) {
      sliderControls.innerHTML = '';
      for (var d = 0; d < heroCards.length; d++) {
        (function(dotIndex) {
          var dot = document.createElement('button');
          dot.className = 'hero-slider-dot' + (dotIndex === currentIndex ? ' active' : '');
          dot.setAttribute('aria-label', 'Slajd ' + (dotIndex + 1));
          dot.addEventListener('click', function() {
            goToSlide(dotIndex);
            resetInterval();
          });
          sliderControls.appendChild(dot);
        })(d);
      }
    }

    function updateDots() {
      var dots = document.querySelectorAll('.hero-slider-dot');
      for (var di = 0; di < dots.length; di++) {
        if (di === currentIndex) {
          dots[di].classList.add('active');
        } else {
          dots[di].classList.remove('active');
        }
      }
    }

    function goToSlide(index) {
      heroCards[currentIndex].classList.remove('active');
      currentIndex = (index + heroCards.length) % heroCards.length;
      heroCards[currentIndex].classList.add('active');
      updateDots();
    }

    function nextSlide() {
      goToSlide(currentIndex + 1);
    }

    function startInterval() {
      if (sliderInterval) {
        clearInterval(sliderInterval);
      }
      sliderInterval = setInterval(nextSlide, HERO_INTERVAL);
    }

    function resetInterval() {
      startInterval();
    }

    var heroSlider = document.querySelector('.hero-slider');
    if (heroSlider) {
      heroSlider.addEventListener('mouseenter', function() {
        if (sliderInterval) {
          clearInterval(sliderInterval);
        }
      });
      heroSlider.addEventListener('mouseleave', function() {
        startInterval();
      });
      var touchStartX = 0;
      var touchEndX = 0;
      heroSlider.addEventListener('touchstart', function(e) {
        touchStartX = e.changedTouches[0].screenX;
      }, { passive: true });
      heroSlider.addEventListener('touchend', function(e) {
        touchEndX = e.changedTouches[0].screenX;
        var diff = touchStartX - touchEndX;
        if (Math.abs(diff) > 50) {
          if (diff > 0) {
            goToSlide(currentIndex + 1);
          } else {
            goToSlide(currentIndex - 1);
          }
          resetInterval();
        }
      }, { passive: true });
    }

    if (document.addEventListener) {
      document.addEventListener('visibilitychange', function() {
        if (document.hidden) {
          if (sliderInterval) {
            clearInterval(sliderInterval);
          }
        } else {
          startInterval();
        }
      });
    }

    startInterval();
  })();

  // ==========================================
  // 4. CHIP FILTERS on Homepage Anime Catalog
  // ==========================================
  (function initChipFilters() {
    var chipContainers = document.querySelectorAll('.filters');
    if (!chipContainers || chipContainers.length === 0) return;

    for (var ci = 0; ci < chipContainers.length; ci++) {
      (function(container) {
        var chips = container.querySelectorAll('.chip');
        for (var cj = 0; cj < chips.length; cj++) {
          chips[cj].addEventListener('click', function(e) {
            var clickedChip = e.currentTarget;
            var parent = clickedChip.closest('.filters');
            if (!parent) return;
            var siblingChips = parent.querySelectorAll('.chip');
            for (var ck = 0; ck < siblingChips.length; ck++) {
              siblingChips[ck].classList.remove('active');
            }
            clickedChip.classList.add('active');
            var filterEvent = new CustomEvent('chipfilterchange', {
              detail: {
                filter: clickedChip.getAttribute('data-filter') || clickedChip.textContent.trim()
              }
            });
            document.dispatchEvent(filterEvent);
          });
        }
      })(chipContainers[ci]);
    }
  })();

  // ==========================================
  // 5. SCHEDULE TABS (if exist on page)
  // ==========================================
  (function initScheduleTabs() {
    var scheduleTabs = document.querySelector('.schedule-tabs');
    if (!scheduleTabs) return;

    var tabItems = scheduleTabs.querySelectorAll('.chip, .schedule-tab, [data-day]');
    if (!tabItems || tabItems.length === 0) {
      tabItems = scheduleTabs.children;
    }

    function activateTab(tabEl) {
      if (!tabEl) return;
      var parentContainer = tabEl.closest('.schedule-tabs');
      if (!parentContainer) return;
      var allTabs = parentContainer.querySelectorAll('.chip, .schedule-tab, [data-day], .schedule-tab-item');
      for (var ti = 0; ti < allTabs.length; ti++) {
        allTabs[ti].classList.remove('active');
      }
      tabEl.classList.add('active');
      var dayFilter = tabEl.getAttribute('data-day');
      if (dayFilter) {
        var allScheduleDays = document.querySelectorAll('.schedule-day');
        for (var d = 0; d < allScheduleDays.length; d++) {
          var dayAttr = allScheduleDays[d].getAttribute('data-day');
          if (dayAttr && dayAttr === dayFilter) {
            allScheduleDays[d].style.display = '';
          } else if (dayAttr) {
            allScheduleDays[d].style.display = 'none';
          }
        }
      }
    }

    for (var ti = 0; ti < tabItems.length; ti++) {
      (function(tab) {
        tab.addEventListener('click', function(e) {
          e.preventDefault();
          activateTab(tab);
        });
      })(tabItems[ti]);
    }
  })();

  // ==========================================
  // TOAST NOTIFICATION HELPER
  // ==========================================
  var toastContainer = null;

  function ensureToastContainer() {
    if (!toastContainer || !document.body.contains(toastContainer)) {
      toastContainer = document.createElement('div');
      toastContainer.className = 'toast-container';
      document.body.appendChild(toastContainer);
    }
    return toastContainer;
  }

  function showToast(message, type, duration) {
    type = type || 'success';
    duration = duration || 3500;
    var container = ensureToastContainer();
    var toast = document.createElement('div');
    toast.className = 'toast toast-' + type;

    var iconMap = {
      success: '\u2713',
      error: '\u2715',
      warning: '\u26A0',
      info: '\u2139'
    };

    var icon = document.createElement('span');
    icon.className = 'toast-icon';
    icon.textContent = iconMap[type] || iconMap.success;
    toast.appendChild(icon);

    var text = document.createElement('span');
    text.textContent = message;
    toast.appendChild(text);

    var closeBtn = document.createElement('button');
    closeBtn.className = 'toast-close';
    closeBtn.innerHTML = '&times;';
    closeBtn.setAttribute('aria-label', 'Zakryt uvedomlenie');
    closeBtn.addEventListener('click', function() {
      dismissToast(toast);
    });
    toast.appendChild(closeBtn);
    container.appendChild(toast);

    requestAnimationFrame(function() {
      requestAnimationFrame(function() {
        toast.classList.add('show');
      });
    });

    if (duration > 0) {
      setTimeout(function() {
        dismissToast(toast);
      }, duration);
    }
    return toast;
  }

  function dismissToast(toast) {
    if (!toast) return;
    toast.classList.add('hide');
    setTimeout(function() {
      if (toast.parentNode) {
        toast.parentNode.removeChild(toast);
      }
    }, 450);
  }

  // ==========================================
  // 6. FILTERS PANEL - Apply button
  // ==========================================
  (function initFiltersPanel() {
    var applyBtn = document.querySelector('.btn-apply-filters');
    if (applyBtn) {
      applyBtn.addEventListener('click', function() {
        var minCount = 48;
        var maxCount = 312;
        var randomCount = Math.floor(Math.random() * (maxCount - minCount + 1)) + minCount;
        var formattedCount = randomCount.toLocaleString('ru-RU');
        showToast('Filtry primeny. Najdeno ' + formattedCount + ' taytlov', 'success', 3500);
      });
    }

    var resetBtn = document.querySelector('.btn-reset-filters');
    if (resetBtn) {
      resetBtn.addEventListener('click', function() {
        var checkboxes = document.querySelectorAll('.filters-panel input[type="checkbox"]');
        for (var cb = 0; cb < checkboxes.length; cb++) {
          checkboxes[cb].checked = false;
        }
        var radios = document.querySelectorAll('.filters-panel input[type="radio"]');
        for (var rb = 0; rb < radios.length; rb++) {
          radios[rb].checked = false;
        }
        var radioPills = document.querySelectorAll('.filters-panel .radio-pill');
        for (var rp = 0; rp < radioPills.length; rp++) {
          radioPills[rp].classList.remove('active');
        }
        var sorts = document.querySelectorAll('.filters-panel .sort-select');
        for (var s = 0; s < sorts.length; s++) {
          sorts[s].selectedIndex = 0;
        }
        showToast('Filtry sbrosheny', 'info', 2500);
      });
    }

    var radioPillsAll = document.querySelectorAll('.radio-pill');
    for (var rpi = 0; rpi < radioPillsAll.length; rpi++) {
      (function(pill) {
        pill.addEventListener('click', function() {
          var group = pill.closest('.filter-radio-group');
          if (!group) return;
          var groupPills = group.querySelectorAll('.radio-pill');
          for (var gpi = 0; gpi < groupPills.length; gpi++) {
            groupPills[gpi].classList.remove('active');
            var innerInput = groupPills[gpi].querySelector('input[type="radio"]');
            if (innerInput) {
              innerInput.checked = false;
            }
          }
          pill.classList.add('active');
          var pillInput = pill.querySelector('input[type="radio"]');
          if (pillInput) {
            pillInput.checked = true;
          }
        });
      })(radioPillsAll[rpi]);
    }
  })();

  // ==========================================
  // 7. COPYRIGHT FORM SUBMIT
  // ==========================================
  (function initCopyrightForm() {
    var copyrightForm = document.querySelector('.contact-form');
    if (!copyrightForm) return;
    var isCopyrightPage = document.body.classList.contains('page-copyright') ||
      (window.location.pathname.indexOf('copyright') !== -1) ||
      copyrightForm.id === 'copyrightForm';
    if (!isCopyrightPage) {
      var allForms = document.querySelectorAll('form');
      for (var af = 0; af < allForms.length; af++) {
      }
    }

    copyrightForm.addEventListener('submit', function(e) {
      e.preventDefault();
      var submitBtn = copyrightForm.querySelector('.btn-submit');
      var originalText = '';
      if (submitBtn) {
        originalText = submitBtn.innerHTML;
        submitBtn.disabled = true;
        submitBtn.style.opacity = '0.7';
        submitBtn.innerHTML = 'Otpravka...';
      }
      setTimeout(function() {
        showToast('Spasibo! Vashe uvedomlenie otpravleno pravovladeltsam. Otvet v techenie 24 chasov na email', 'success', 5000);
        copyrightForm.reset();
        if (submitBtn) {
          submitBtn.disabled = false;
          submitBtn.style.opacity = '';
          submitBtn.innerHTML = originalText || 'Otpravit uvedomlenie';
        }
      }, 800);
    });
  })();

  // ==========================================
  // 8. SUBSCRIBE FORM SUBMIT
  // ==========================================
  (function initSubscribeForm() {
    var subscribeForm = document.querySelector('.subscribe-form');
    if (!subscribeForm) return;

    subscribeForm.addEventListener('submit', function(e) {
      e.preventDefault();
      var emailInput = subscribeForm.querySelector('.subscribe-input');
      var emailVal = emailInput ? emailInput.value.trim() : '';

      if (emailInput && !emailVal) {
        showToast('Pozhaluysta, vvedite vash email', 'warning', 3000);
        if (emailInput.focus) {
          emailInput.focus();
        }
        return;
      }

      if (emailVal && emailVal.indexOf('@') === -1) {
        showToast('Vvedite korrektny email adres', 'warning', 3000);
        if (emailInput.focus) {
          emailInput.focus();
        }
        return;
      }

      var subBtn = subscribeForm.querySelector('.btn-primary, button[type="submit"]');
      if (subBtn) {
        subBtn.disabled = true;
        subBtn.style.opacity = '0.7';
      }

      setTimeout(function() {
        showToast('\u2705 Podpiska oformlena! Novosti anime na email kazhduyu pyatnitsu.', 'success', 4500);
        subscribeForm.reset();
        if (subBtn) {
          subBtn.disabled = false;
          subBtn.style.opacity = '';
        }
      }, 600);
    });
  })();

  // ==========================================
  // 9. SCROLL TO TOP BUTTON
  // ==========================================
  (function initScrollToTop() {
    var scrollBtn = document.querySelector('.scroll-to-top');
    if (!scrollBtn) {
      scrollBtn = document.createElement('button');
      scrollBtn.className = 'scroll-to-top';
      scrollBtn.setAttribute('aria-label', 'Naverkh');
      scrollBtn.innerHTML = '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="18 15 12 9 6 15"></polyline></svg>';
      document.body.appendChild(scrollBtn);
    }

    var SCROLL_THRESHOLD = 400;
    var ticking = false;

    function updateScrollButton() {
      var scrollY = window.pageYOffset || document.documentElement.scrollTop;
      if (scrollY > SCROLL_THRESHOLD) {
        scrollBtn.classList.add('visible');
      } else {
        scrollBtn.classList.remove('visible');
      }
      ticking = false;
    }

    window.addEventListener('scroll', function() {
      if (!ticking) {
        window.requestAnimationFrame(updateScrollButton);
        ticking = true;
      }
    }, { passive: true });

    scrollBtn.addEventListener('click', function() {
      if (window.scrollTo) {
        window.scrollTo({ top: 0, behavior: 'smooth' });
      } else {
        document.body.scrollTop = 0;
        document.documentElement.scrollTop = 0;
      }
    });

    updateScrollButton();
  })();

  // ==========================================
  // 10. SCROLL SPY for nav-links
  // ==========================================
  (function initScrollSpy() {
    var sectionIds = ['catalog', 'schedule', 'manga', 'features', 'subscribe', 'about'];
    var sections = [];
    for (var si = 0; si < sectionIds.length; si++) {
      var sec = document.getElementById(sectionIds[si]);
      if (sec) {
        sections.push({ id: sectionIds[si], element: sec });
      }
    }
    if (sections.length === 0) return;

    var navLinks = document.querySelectorAll('.nav-link[href^="#"]');
    if (!navLinks || navLinks.length === 0) return;

    var spyTicking = false;

    function updateActiveNav() {
      var scrollPos = (window.pageYOffset || document.documentElement.scrollTop) + 120;
      var currentId = null;

      for (var spi = 0; spi < sections.length; spi++) {
        var secTop = sections[spi].element.offsetTop;
        var secBottom = secTop + sections[spi].element.offsetHeight;
        if (scrollPos >= secTop && scrollPos < secBottom) {
          currentId = sections[spi].id;
        }
      }

      if (currentId) {
        for (var nli = 0; nli < navLinks.length; nli++) {
          var href = navLinks[nli].getAttribute('href');
          if (href === '#' + currentId) {
            navLinks[nli].classList.add('active');
          } else if (href && href.charAt(0) === '#') {
            var matchingSection = document.querySelector(href);
            if (matchingSection) {
              var isTracked = false;
              for (var ts = 0; ts < sections.length; ts++) {
                if ('#' + sections[ts].id === href) {
                  isTracked = true;
                  break;
                }
              }
              if (isTracked) {
                navLinks[nli].classList.remove('active');
              }
            }
          }
        }
      }
      spyTicking = false;
    }

    window.addEventListener('scroll', function() {
      if (!spyTicking) {
        window.requestAnimationFrame(updateActiveNav);
        spyTicking = true;
      }
    }, { passive: true });

    updateActiveNav();
  })();

  // ==========================================
  // 11. SMOOTH SCROLL for anchor links
  // ==========================================
  (function initSmoothScroll() {
    var anchorLinks = document.querySelectorAll('a[href^="#"]');
    if (!anchorLinks || anchorLinks.length === 0) return;

    for (var ali = 0; ali < anchorLinks.length; ali++) {
      (function(link) {
        link.addEventListener('click', function(e) {
          var href = link.getAttribute('href');
          if (!href || href === '#') return;
          if (href.length <= 1) return;
          var target = document.querySelector(href);
          if (!target) return;
          e.preventDefault();

          var headerOffset = 80;
          var elementPosition = target.getBoundingClientRect().top;
          var offsetPosition = elementPosition + (window.pageYOffset || document.documentElement.scrollTop) - headerOffset;

          if (window.scrollTo) {
            window.scrollTo({ top: offsetPosition, behavior: 'smooth' });
          } else {
            target.scrollIntoView({ behavior: 'smooth', block: 'start' });
          }

          if (history && history.pushState) {
            try {
              history.pushState(null, '', href);
            } catch (err) {
            }
          }

          var mobileNav = document.querySelector('.nav.mobile.open');
          if (mobileNav) {
            mobileNav.classList.remove('open');
          }
        });
      })(anchorLinks[ali]);
    }
  })();

  // ==========================================
  // HEADER SCROLL EFFECT + MOBILE MENU
  // ==========================================
  (function initHeaderAndMenu() {
    var header = document.querySelector('.header');
    if (header) {
      var headerTicking = false;
      window.addEventListener('scroll', function() {
        if (!headerTicking) {
          window.requestAnimationFrame(function() {
            var scrollY = window.pageYOffset || document.documentElement.scrollTop;
            if (scrollY > 10) {
              header.classList.add('scrolled');
            } else {
              header.classList.remove('scrolled');
            }
            headerTicking = false;
          });
          headerTicking = true;
        }
      }, { passive: true });
    }

    var menuToggle = document.querySelector('.menu-toggle');
    var mobileNav = document.querySelector('.nav.mobile');
    if (menuToggle && mobileNav) {
      menuToggle.addEventListener('click', function(e) {
        e.stopPropagation();
        mobileNav.classList.toggle('open');
        var isOpen = mobileNav.classList.contains('open');
        menuToggle.setAttribute('aria-expanded', isOpen ? 'true' : 'false');
      });
      document.addEventListener('click', function(e) {
        if (!mobileNav.classList.contains('open')) return;
        if (mobileNav.contains(e.target) || menuToggle.contains(e.target)) return;
        mobileNav.classList.remove('open');
      });
      document.addEventListener('keydown', function(e) {
        if (e.key === 'Escape' && mobileNav.classList.contains('open')) {
          mobileNav.classList.remove('open');
        }
      });
    }
  })();

  // ==========================================
  // PAGINATION HANDLER (visual active state)
  // ==========================================
  (function initPagination() {
    var paginationBtns = document.querySelectorAll('.pagination .page-btn');
    if (!paginationBtns || paginationBtns.length === 0) return;
    for (var pbi = 0; pbi < paginationBtns.length; pbi++) {
      (function(btn) {
        btn.addEventListener('click', function(e) {
          if (btn.disabled) return;
          var parentPag = btn.closest('.pagination');
          if (!parentPag) return;
          var allBtns = parentPag.querySelectorAll('.page-btn');
          for (var ab = 0; ab < allBtns.length; ab++) {
            allBtns[ab].classList.remove('active');
          }
          if (btn.textContent.trim().match(/^\d+$/)) {
            btn.classList.add('active');
          }
        });
      })(paginationBtns[pbi]);
    }
  })();

  // ==========================================
  // ANIMATED COUNTERS for stats
  // ==========================================
  (function initAnimatedCounters() {
    var statNums = document.querySelectorAll('.stat-num');
    if (!statNums || statNums.length === 0) return;

    function animateCounter(el) {
      var finalText = el.textContent.trim();
      var numericPart = finalText.replace(/[^0-9]/g, '');
      var suffix = finalText.replace(/[0-9]/g, '');
      var target = parseInt(numericPart, 10);
      if (!target || isNaN(target)) return;
      var duration = 1500;
      var startTime = null;
      var startValue = 0;

      function step(timestamp) {
        if (!startTime) {
          startTime = timestamp;
        }
        var progress = Math.min((timestamp - startTime) / duration, 1);
        var easeOutQuart = 1 - Math.pow(1 - progress, 4);
        var current = Math.floor(startValue + (target - startValue) * easeOutQuart);
        el.textContent = current.toLocaleString('ru-RU') + suffix;
        if (progress < 1) {
          window.requestAnimationFrame(step);
        } else {
          el.textContent = target.toLocaleString('ru-RU') + suffix;
        }
      }
      window.requestAnimationFrame(step);
    }

    if ('IntersectionObserver' in window) {
      var counterObserver = new IntersectionObserver(function(entries) {
        for (var ei = 0; ei < entries.length; ei++) {
          if (entries[ei].isIntersecting) {
            animateCounter(entries[ei].target);
            counterObserver.unobserve(entries[ei].target);
          }
        }
      }, { threshold: 0.5 });
      for (var ci = 0; ci < statNums.length; ci++) {
        counterObserver.observe(statNums[ci]);
      }
    } else {
      for (var cj = 0; cj < statNums.length; cj++) {
        animateCounter(statNums[cj]);
      }
    }
  })();

  // ==========================================
  // MANGA PROGRESS BAR ANIMATION
  // ==========================================
  (function initMangaProgress() {
    var progressFills = document.querySelectorAll('.manga-progress-fill');
    if (!progressFills || progressFills.length === 0) return;
    if ('IntersectionObserver' in window) {
      var progObserver = new IntersectionObserver(function(entries) {
        for (var pei = 0; pei < entries.length; pei++) {
          if (entries[pei].isIntersecting) {
            (function(fillEl) {
              var targetWidth = fillEl.style.width || fillEl.getAttribute('data-width') || '50%';
              fillEl.style.width = '0%';
              requestAnimationFrame(function() {
                setTimeout(function() {
                  fillEl.style.width = targetWidth;
                }, 100);
              });
            })(entries[pei].target);
            progObserver.unobserve(entries[pei].target);
          }
        }
      }, { threshold: 0.3 });
      for (var pfi = 0; pfi < progressFills.length; pfi++) {
        progObserver.observe(progressFills[pfi]);
      }
    }
  })();

  // ==========================================
  // CARD HOVER HANDLERS
  // ==========================================
  (function initCardHandlers() {
    var reduceMotion = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    if (reduceMotion) return;
    var animeCards = document.querySelectorAll('.anime-card, .manga-card, .feature-card, .team-card');
    if (!animeCards || animeCards.length === 0) return;
    for (var cardi = 0; cardi < animeCards.length; cardi++) {
      (function(card) {
        card.addEventListener('mouseenter', function() {
        });
        card.addEventListener('mouseleave', function() {
          card.style.transform = '';
        });
      })(animeCards[cardi]);
    }
  })();

  // ==========================================
  // FORM INPUTS STATE HANDLER
  // ==========================================
  (function initFormInputs() {
    var formInputs = document.querySelectorAll('.form-input, .form-textarea, .form-select, .search-input, .subscribe-input');
    if (!formInputs || formInputs.length === 0) return;
    for (var fii = 0; fii < formInputs.length; fii++) {
      (function(input) {
        function checkValue() {
          if (input.value && input.value.length > 0) {
            input.classList.add('has-value');
          } else {
            input.classList.remove('has-value');
          }
        }
        input.addEventListener('input', checkValue);
        input.addEventListener('blur', checkValue);
        input.addEventListener('change', checkValue);
        checkValue();
      })(formInputs[fii]);
    }
  })();

  // ==========================================
  // VIEW TOGGLE (grid/list view for catalogs)
  // ==========================================
  (function initViewToggle() {
    var viewToggles = document.querySelectorAll('.view-toggle');
    if (!viewToggles || viewToggles.length === 0) return;
    for (var vti = 0; vti < viewToggles.length; vti++) {
      (function(toggle) {
        var buttons = toggle.querySelectorAll('.view-toggle-btn');
        for (var vbi = 0; vbi < buttons.length; vbi++) {
          buttons[vbi].addEventListener('click', function(e) {
            var clicked = e.currentTarget;
            var parent = clicked.closest('.view-toggle');
            if (!parent) return;
            var allBtns = parent.querySelectorAll('.view-toggle-btn');
            for (var abv = 0; abv < allBtns.length; abv++) {
              allBtns[abv].classList.remove('active');
            }
            clicked.classList.add('active');
            var viewType = clicked.getAttribute('data-view') || 'grid';
            var catalog = document.querySelector('.catalog-grid, .anime-grid, .manga-grid');
            if (catalog) {
              if (viewType === 'list') {
                catalog.style.gridTemplateColumns = '1fr';
                catalog.style.gap = '12px';
              } else {
                catalog.style.gridTemplateColumns = '';
                catalog.style.gap = '';
              }
            }
          });
        }
      })(viewToggles[vti]);
    }
  })();

  // ==========================================
  // TEAM CARD ANIMATIONS + SOCIAL LINKS
  // ==========================================
  (function initTeamCards() {
    var teamCards = document.querySelectorAll('.team-card');
    if (!teamCards || teamCards.length === 0) return;
    for (var tci = 0; tci < teamCards.length; tci++) {
      (function(tc) {
        var avatar = tc.querySelector('.team-avatar');
        if (avatar) {
          tc.addEventListener('mouseenter', function() {
            avatar.style.transform = 'scale(1.08) rotate(-3deg)';
            avatar.style.transition = 'transform 0.4s cubic-bezier(0.4, 0, 0.2, 1)';
          });
          tc.addEventListener('mouseleave', function() {
            avatar.style.transform = '';
          });
        }
      })(teamCards[tci]);
    }
  })();

  // ==========================================
  // SCHEDULE ITEM CLICK HANDLERS
  // ==========================================
  (function initScheduleItems() {
    var scheduleItems = document.querySelectorAll('.schedule-item');
    if (!scheduleItems || scheduleItems.length === 0) return;
    for (var sii = 0; sii < scheduleItems.length; sii++) {
      (function(item) {
        item.addEventListener('click', function() {
          var titleEl = item.querySelector('.schedule-title');
          if (titleEl) {
            var titleText = titleEl.textContent.trim();
            var epEl = item.querySelector('.schedule-ep');
            var epText = epEl ? epEl.textContent.trim() : '';
          }
        });
      })(scheduleItems[sii]);
    }
  })();

  // ==========================================
  // NAVIGATION ACTIVE STATE FOR CURRENT PAGE
  // ==========================================
  (function initNavActivePage() {
    var currentPath = window.location.pathname;
    var fileName = currentPath.substring(currentPath.lastIndexOf('/') + 1);
    if (!fileName) {
      fileName = 'index.html';
    }
    var navLinks = document.querySelectorAll('.nav-link');
    for (var nli = 0; nli < navLinks.length; nli++) {
      var linkHref = navLinks[nli].getAttribute('href');
      if (!linkHref || linkHref.charAt(0) === '#') continue;
      var linkFile = linkHref.substring(linkHref.lastIndexOf('/') + 1);
      if (linkFile === fileName) {
        navLinks[nli].classList.add('active');
      } else if (fileName === '' && (linkFile === 'index.html' || linkFile === '/')) {
        navLinks[nli].classList.add('active');
      }
    }
  })();

  // ==========================================
  // DOCUMENT TITLE DECORATION (favicon-like subtle effect
  // ==========================================
  (function initDocumentEffects() {
    var originalTitle = document.title;
    var isWindowFocused = true;
    if (document.addEventListener) {
      document.addEventListener('visibilitychange', function() {
        isWindowFocused = !document.hidden;
        try {
          if (document.hidden) {
            document.title = '\u2728 ' + originalTitle;
          } else {
            document.title = originalTitle;
          }
        } catch (err) {
        }
      });
    }
    if (window.addEventListener) {
      window.addEventListener('focus', function() {
        isWindowFocused = true;
        document.title = originalTitle;
      });
      window.addEventListener('blur', function() {
        isWindowFocused = false;
      });
    }
  })();

  // ==========================================
  // ANIME CARD QUICK ACTIONS (double click simulate)
  // ==========================================
  (function initAnimeCardActions() {
    var animeCards = document.querySelectorAll('.anime-card');
    if (!animeCards || animeCards.length === 0) return;
    for (var aci = 0; aci < animeCards.length; aci++) {
      (function(card, idx) {
        card.setAttribute('tabindex', '0');
        card.setAttribute('role', 'button');
        card.addEventListener('keydown', function(e) {
          if (e.key === 'Enter' || e.key === ' ') {
            e.preventDefault();
          }
        });
      })(animeCards[aci], aci);
    }
  })();

  // ==========================================
  // FOOTER YEAR AUTO-UPDATE
  // ==========================================
  (function initFooterYear() {
    var footerCopy = document.querySelector('.footer-copy');
    if (!footerCopy) return;
    var currentYear = new Date().getFullYear();
    var text = footerCopy.innerHTML;
    if (text && text.indexOf('2024') !== -1) {
      footerCopy.innerHTML = text.replace(/202[0-9]/g, String(currentYear));
    } else if (text && text.indexOf('2025') !== -1) {
      footerCopy.innerHTML = text.replace(/202[0-9]/g, String(currentYear));
    } else if (text && text.indexOf('2026') !== -1) {
      footerCopy.innerHTML = text.replace(/202[0-9]/g, String(currentYear));
    }
  })();

  // ==========================================
  // CONTENT COUNT UPDATER (randomized for catalogs
  // ==========================================
  (function initContentCount() {
    var countEls = document.querySelectorAll('.content-count');
    if (!countEls || countEls.length === 0) return;
    for (var cei = 0; cei < countEls.length; cei++) {
      (function(el) {
        var existingText = el.textContent;
        if (existingText && existingText.match(/\d+/)) {
          return;
        }
        var baseMin = 120;
        var baseMax = 2800;
        var rnd = Math.floor(Math.random() * (baseMax - baseMin + 1)) + baseMin;
        el.textContent = 'Vsego: ' + rnd.toLocaleString('ru-RU') + ' taytlov';
      })(countEls[cei]);
    }
  })();

  // ==========================================
  // FORM CHECKBOX GROUP SYNC
  // ==========================================
  (function initCheckboxGroups() {
    var checkboxGroups = document.querySelectorAll('.form-checkbox-group');
    if (!checkboxGroups || checkboxGroups.length === 0) return;
    for (var cgi = 0; cgi < checkboxGroups.length; cgi++) {
      (function(group) {
        var cb = group.querySelector('input[type="checkbox"]');
        var lbl = group.querySelector('label');
        if (cb && lbl) {
          lbl.addEventListener('click', function(e) {
          });
          group.addEventListener('click', function(e) {
            if (e.target === cb || e.target.tagName === 'LABEL' || e.target.tagName === 'A') return;
            cb.checked = !cb.checked;
            var event = new Event('change', { bubbles: true });
            cb.dispatchEvent(event);
          });
        }
      })(checkboxGroups[cgi]);
    }
  })();

  // ==========================================
  // EXPOSE PUBLIC API
  // ==========================================
  window.AniMangaApp = {
    showToast: showToast,
    setTheme: function(theme) {
      localStorage.setItem('theme', theme === 'light' ? 'light' : 'dark');
      var toggle = document.querySelector('.theme-toggle');
      if (toggle) {
        toggle.click();
        var cur = document.body.classList.contains('light-theme') ? 'light' : 'dark';
        if (cur !== (theme === 'light' ? 'light' : 'dark')) {
          toggle.click();
        }
      }
    },
    scrollToTop: function() {
      if (window.scrollTo) {
        window.scrollTo({ top: 0, behavior: 'smooth' });
      }
    },
    goToSlide: function(idx) {
      var cards = document.querySelectorAll('.hero-card');
      if (!cards || cards.length === 0) return;
      for (var ci = 0; ci < cards.length; ci++) {
        cards[ci].classList.remove('active');
      }
      var realIdx = (idx + cards.length) % cards.length;
      cards[realIdx].classList.add('active');
    },
    version: '1.0.0'
  };

  // ==========================================
  // FINAL: Console banner (safe console output)
  // ==========================================
  if (window.console && typeof console.log === 'function') {
    try {
      var bannerStyle = 'background: linear-gradient(135deg, #7c3aed 0%, #0ea5e9 100%); color: white; padding: 8px 16px; border-radius: 8px; font-weight: 700; font-size: 13px;';
      var subStyle = 'color: #94a3b8; font-size: 12px; padding: 4px 0;';
      console.log('%c  AniManga Hub  ', bannerStyle);
      console.log('%c  Versiya: 1.0.0  ', subStyle);
      console.log('%c  Zagruzheno: ' + new Date().toLocaleString('ru-RU') + '  ', subStyle);
    } catch (e) {
    }
  }

});
