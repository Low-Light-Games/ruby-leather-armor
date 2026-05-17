import React from "react";
import "./FrontPage.scss";
import "./RedditLanding.scss";

const RedditLanding: React.FC = () => (
  <div className="fp">
    <header className="fp-header">
      <div className="fp-header__inner">
        <p className="fp-typewriter rl-notice">
          Ho there, Redditor. Stay thy course a moment and indulge an old man.
        </p>
        <h1 className="fp-header__title">Leatherarmor</h1>
        <hr className="fp-header__rule" />
      </div>
    </header>

    <div className="fp-illustration">
      <div className="fp-illustration__frame">
        <video
          src="/videos/reddit-map-video.mp4"
          autoPlay
          loop
          muted
          playsInline
          className="fp-illustration__img"
        />
      </div>
      <p className="fp-illustration__caption">
        Fig. 1. — A map, half-finished. Like the project itself.
      </p>
    </div>

    <main className="fp-main">

      <section className="fp-section">
        <p>
          Elminster reference aside, thanks for taking the time to check us out.
        </p>
        <p>
          Leatherarmor is supposed to be a solo RPG love letter to the likes of{" "}
          <em>Chainmail</em> and early Gygaxian dungeons. We want that unforgiving,
          ruthless edge that makes it all the more fun, and we want the main
          characters to be simple adventurers with low success odds at first.
        </p>
      </section>

      <hr className="fp-divider" />

      <section className="fp-section">
        <h2 className="fp-section__heading">Why wouldn't you just play some Pathfinder CRPG or BG3?</h2>
        <p>
          While those are great games, we very much want somewhere where you can be
          truly free and not railroaded at all. We want a world where you can just
          decide to call the city watch on someone because that is sensible, or
          decide you'll actually live by the dungeon entrance for a couple of weeks
          to study access patterns. You know when you are, out of nowhere, forced to
          choose between 2 convoluted bad plans? We want that to never happen here.
          It's the whole point, so the first principle is "freedom", and with that
          freedom, you can undertake dangerous adventures and, because you were truly
          free, it feels fairer when you do fail. You got to try what you wanted, and
          it didn't pan out, as opposed to "I was railroaded into this and, to the
          surprise of no one, it failed". Never win the fight and lose in the
          cutscene, never be fooled by an obviously duplicitous NPC.
        </p>
      </section>

      <hr className="fp-divider" />

      <div className="fp-illustration">
        <div className="fp-illustration__frame">
          <video
            src="/videos/reddit-descent-video.mp4"
            autoPlay
            loop
            muted
            playsInline
            className="fp-illustration__img"
          />
        </div>
        <p className="fp-illustration__caption">
          Fig. 2. — The descent. Your torch will not last the level.
        </p>
      </div>

      <hr className="fp-divider" />

      <section className="fp-section">
        <h2 className="fp-section__heading">On the state of Leatherarmor.</h2>
        <p>
          We can tell you this: it's not where we want it to be. We want to write
          more stories. We want to empower users to create their own stories that
          others can play. We eventually want to allow 2–3 players to tackle an
          adventure together. We want NPC companions to be exportable from one
          adventure to another.
        </p>
        <p>
          But those are grandiose ideas. First, we need your help in improving the
          basics. We need to ensure combat can start seamlessly with an NPC who was
          never meant to be a combatant. We need to make sure the pack of wolves can
          be reliably animal-handled mid-combat, with a reasonable (very hard) DC. We
          need to make sure the enemies don't get stuck on each other trying to find
          you and attack you on the combat grid. Some of those are easy — just
          superior coding necessary — some will probably require further fine-tuning
          of AI models.
        </p>
      </section>

      <hr className="fp-divider" />

      <section className="fp-section fp-section--closing">
        <h2 className="fp-section__heading">What is the help we want?</h2>
        <p>
          We just want you to play the game and let us know what sucks, what works,
          and what's meh. We just need the exposure right now, and although there are
          paid plans, the money is not the most important part (it does pay for the
          servers, though). The most important thing is your feedback. We get to code
          and handle the AI hallucinations, you get to play and complain to us.
          Sounds good? If so, please try out by clicking the button below.
        </p>
        <div className="fp-cta-wrap">
          <a href="/adventures/new" className="fp-cta-btn">
            Roll a Character
          </a>
        </div>
      </section>

    </main>

    <footer className="fp-footer">
      <nav className="fp-footer__links">
        <a href="/legal" className="fp-typewriter fp-footer__link">Open Game License</a>
        <a href="/privacy" className="fp-typewriter fp-footer__link">Privacy</a>
      </nav>
      <p className="fp-typewriter fp-footer__copy">&copy; {new Date().getFullYear()} leatherarmor.io</p>
    </footer>
  </div>
);

export default RedditLanding;
