// PresentationMode: full-screen layer mounted at the presentation route
// (spec 09 §5.3 shell contract). Ships complete and compiling: the scaffold
// step drops this file into src/presentation/ alongside slides.template.ts
// (renamed to slides.ts) and adjusts the two app-specific imports below
// ('../i18n', '../theme') to match wherever the target app's own hooks live.
//
// This component intentionally does NOT instantiate ThemeProvider or
// I18nProvider itself. It is mounted inside the app's existing router tree,
// underneath the app's own providers, and reads them via hooks — the SAME
// providers the app uses, never copies (spec 09 §5.3).
import { useCallback, useEffect, useMemo, useState } from 'react';
import type { ReactNode } from 'react';
import { slides } from './slides.template';
import type { Slide } from './slides.template';
import { useI18n } from '../i18n';
import { useTheme } from '../theme';

export interface PresentationModeProps {
  /**
   * Mounts the real, running app for the guided-demo overlay
   * (kind: 'live-demo', "Enter the app"). Left as a prop rather than a
   * direct import so this template has no hard dependency on the app's
   * root component path.
   */
  renderApp: () => ReactNode;
  /** Called when the presenter exits the deck entirely (Esc at top level). */
  onExit?: () => void;
}

interface SummaryBeat {
  id: string;
  titleKey: string;
  leadKey: string;
}

/** Naive `{token}` interpolation — no i18n formatting library, no deps. */
function format(template: string, params: Record<string, string | number>): string {
  return Object.entries(params).reduce(
    (acc, [key, value]) => acc.split(`{${key}}`).join(String(value)),
    template,
  );
}

/**
 * True when the key event originates from a control that consumes keyboard
 * input itself (text fields, contenteditable). Deck navigation must never
 * steal keystrokes from these — e.g. typing a space or an arrow key inside
 * a live-demo form must not flip slides.
 */
function isTextEntryTarget(target: EventTarget | null): boolean {
  if (!(target instanceof HTMLElement)) return false;
  if (target.isContentEditable) return true;
  const tag = target.tagName;
  return tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT';
}

export function PresentationMode({ renderApp, onExit }: PresentationModeProps) {
  const { t } = useI18n();
  const { theme } = useTheme();

  const [currentIndex, setCurrentIndex] = useState(0);
  const [overlayActive, setOverlayActive] = useState(false);
  const [overlayStep, setOverlayStep] = useState(0);

  const total = slides.length;
  const currentSlide: Slide = slides[currentIndex];
  const demoSteps = currentSlide.demoSteps ?? [];

  // Summary slide (kind: 'summary'): assembled at render time from every
  // slide that is neither a bookend (title/close) nor the summary itself —
  // slides 2-6 of the 8-slide default spine (problem, status-quo, solution,
  // benefits, roadmap). Computed from the live deck, never hand-copied, so
  // it cannot drift (spec 09 §5.3 shell contract).
  const summaryBeats: SummaryBeat[] = useMemo(
    () =>
      slides
        .filter((slide) => slide.kind !== 'summary' && slide.id !== 'title' && slide.id !== 'close')
        .map((slide) => ({ id: slide.id, titleKey: slide.titleKey, leadKey: slide.leadKey })),
    [],
  );

  const goTo = useCallback(
    (index: number) => {
      setCurrentIndex(Math.min(Math.max(index, 0), total - 1));
    },
    [total],
  );

  const goPrev = useCallback(() => goTo(currentIndex - 1), [currentIndex, goTo]);
  const goNext = useCallback(() => goTo(currentIndex + 1), [currentIndex, goTo]);

  const enterGuidedDemo = useCallback(() => {
    setOverlayStep(0);
    setOverlayActive(true);
  }, []);

  const exitGuidedDemo = useCallback(() => {
    setOverlayActive(false);
    setOverlayStep(0);
  }, []);

  const overlayNextStep = useCallback(() => {
    setOverlayStep((step) => Math.min(step + 1, Math.max(demoSteps.length - 1, 0)));
  }, [demoSteps.length]);

  const overlayPrevStep = useCallback(() => {
    setOverlayStep((step) => Math.max(step - 1, 0));
  }, []);

  useEffect(() => {
    function handleKeyDown(event: KeyboardEvent) {
      // Never intercept keys while the user is typing in a form field or
      // contenteditable region (slide bodies and the live-demo app contain
      // real, interactive UI).
      if (isTextEntryTarget(event.target)) {
        return;
      }

      if (overlayActive) {
        if (event.key === 'Escape') {
          event.preventDefault();
          exitGuidedDemo();
        } else if (event.key === 'ArrowRight') {
          event.preventDefault();
          overlayNextStep();
        } else if (event.key === 'ArrowLeft') {
          event.preventDefault();
          overlayPrevStep();
        }
        return;
      }

      // Space only advances when focus is NOT on an interactive control:
      // a focused button/link must keep its native Space activation
      // (accessibility regression otherwise).
      const interactiveHasFocus =
        event.target instanceof HTMLElement &&
        event.target.closest('button, a[href], [role="button"], [tabindex]') !== null;

      if (event.key === 'ArrowRight' || (event.key === ' ' && !interactiveHasFocus)) {
        event.preventDefault();
        goNext();
      } else if (event.key === 'ArrowLeft') {
        event.preventDefault();
        goPrev();
      } else if (event.key === 'Home') {
        event.preventDefault();
        goTo(0);
      } else if (event.key === 'End') {
        event.preventDefault();
        goTo(total - 1);
      } else if (event.key === 'Escape') {
        event.preventDefault();
        onExit?.();
      } else if (/^[1-9]$/.test(event.key)) {
        event.preventDefault();
        goTo(Number(event.key) - 1);
      }
    }

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [
    overlayActive,
    goNext,
    goPrev,
    goTo,
    total,
    onExit,
    exitGuidedDemo,
    overlayNextStep,
    overlayPrevStep,
  ]);

  if (overlayActive) {
    const step = demoSteps[overlayStep];
    return (
      <div className="presentation-guided-demo" data-theme={theme} role="dialog" aria-modal="true">
        {renderApp()}
        {step ? (
          <div className="presentation-guided-demo__overlay">
            <div className="presentation-guided-demo__backdrop" />
            <div className="presentation-guided-demo__spotlight" data-target={step.target} />
            <div className="presentation-guided-demo__caption">
              <p>{t(step.captionKey)}</p>
              <div className="presentation-guided-demo__controls">
                <button type="button" onClick={overlayPrevStep} disabled={overlayStep === 0}>
                  {t('presentation.nav.prevStep')}
                </button>
                <button
                  type="button"
                  onClick={overlayNextStep}
                  disabled={overlayStep >= demoSteps.length - 1}
                >
                  {t('presentation.nav.nextStep')}
                </button>
                <button type="button" onClick={exitGuidedDemo}>
                  {t('presentation.nav.backToSlides')}
                </button>
              </div>
            </div>
          </div>
        ) : null}
      </div>
    );
  }

  const SlideBody = currentSlide.body;

  return (
    <div className="presentation-mode" data-theme={theme}>
      <div className="presentation-mode__slide">
        {currentSlide.kind === 'summary' ? (
          <div className="presentation-mode__summary">
            <h1>{t(currentSlide.titleKey)}</h1>
            <ul>
              {summaryBeats.map((beat) => (
                <li key={beat.id}>
                  <strong>{t(beat.titleKey)}</strong>
                  <span>{t(beat.leadKey)}</span>
                </li>
              ))}
            </ul>
          </div>
        ) : (
          <SlideBody />
        )}

        {currentSlide.kind === 'live-demo' ? (
          <button type="button" className="presentation-mode__enter-app" onClick={enterGuidedDemo}>
            {t('presentation.nav.enterApp')}
          </button>
        ) : null}
      </div>

      <nav className="presentation-mode__controls" aria-label={t('presentation.nav.controlsLabel')}>
        <button type="button" onClick={goPrev} disabled={currentIndex === 0}>
          {t('presentation.nav.prev')}
        </button>

        {/* Plain buttons inside <nav>, current slide flagged via aria-current.
            Deliberately NOT a WAI-ARIA tablist: there are no tabpanels or
            roving-tabindex here, and half a tabs pattern is worse for
            assistive tech than honest navigation buttons. */}
        <div className="presentation-mode__progress">
          {slides.map((slide, index) => (
            <button
              key={slide.id}
              type="button"
              aria-current={index === currentIndex ? 'true' : undefined}
              aria-label={format(t('presentation.nav.slideOf'), { n: index + 1, total })}
              className={
                index === currentIndex
                  ? 'presentation-mode__dot presentation-mode__dot--active'
                  : 'presentation-mode__dot'
              }
              onClick={() => goTo(index)}
            />
          ))}
        </div>

        <button type="button" onClick={goNext} disabled={currentIndex === total - 1}>
          {t('presentation.nav.next')}
        </button>
      </nav>
    </div>
  );
}
