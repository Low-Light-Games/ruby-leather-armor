import React from "react";
import "./FrontPage.scss";
import "./RedditLanding.scss";

const RedditLanding: React.FC = () => (
  <div className="fp">
    <header className="fp-header">
      <div className="fp-header__inner">
        <p className="fp-typewriter rl-notice">
          A Notice to Travelers from Reddit
        </p>
        <h1 className="fp-header__title">Leatherarmor</h1>
        <hr className="fp-header__rule" />
        <p className="fp-typewriter fp-header__subtitle">
          A Work in Progress —
          <br />
          An AI Referee for Solo Pathfinder, in the Old Style
        </p>
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
        <h2 className="fp-section__heading">We Should Say This Plainly First</h2>
        <p>
          Leatherarmor is not finished. If you have arrived here from an
          advertisement on Reddit, you should know that what we have is a working
          sketch — enough to play, enough to die in, enough to suggest what the
          thing wants to become — but not the polished product we hope it will one
          day be. We are showing it to you early because we would rather have honest
          company on the road than pretend we are further along than we are.
        </p>
        <p>
          What follows is what we are building, why, and what we know is still
          broken. Nothing more flattering than that.
        </p>
      </section>

      <hr className="fp-divider" />

      <section className="fp-section">
        <h2 className="fp-section__heading">What We Borrow From <em>Chainmail</em></h2>
        <p>
          The instinct behind Leatherarmor is older than most of the games on the
          shelf today. We take our cue from <em>Chainmail</em> and the earliest
          dungeon-crawls — rule-heavy, unforgiving, a little baroque. The kind of
          game where the rulebook does not exist to keep you safe; it exists so
          that, when the thing in the pit kills you, both sides agree about how it
          happened.
        </p>
        <p>
          We are not interested in streamlined power fantasy. We are interested in
          torch counts and reaction rolls, in morale, in the cold arithmetic of a
          first-level character standing in front of a door they have no business
          opening. The Pathfinder rules give us the substance; the older tradition
          gives us the disposition.
        </p>
        <p>
          You are not a hero. You are an adventurer. The dungeon will treat you
          accordingly.
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
        <h2 className="fp-section__heading">The Rule Problem, and Why We Are Spending Our Time On It</h2>
        <p>
          Anyone who has sat a language model down and asked it to run a serious
          tabletop game knows the failure mode. The prose is good. The atmosphere
          is good. The rules are, charitably, suggestions. Hit points drift. Saves
          are forgotten. The model invents a feat you do not have and lets you use
          it. After an hour you are no longer playing Pathfinder — you are playing
          a courteous improv partner who has heard of Pathfinder.
        </p>
        <p>
          For a casual session, that is fine. For a serious solo campaign — the
          kind you want to come back to, the kind whose stakes you actually
          believe — it is not. The whole point of an unforgiving system is that
          the rules are the contract. If the referee will not hold the line, the
          danger is theatrical.
        </p>
        <p>
          So most of our work is not on prose. It is on the unglamorous
          scaffolding: a deterministic rules engine that resolves dice, tracks
          state, enforces conditions, and refuses to let the language model
          quietly forgive a failed save. The AI narrates. The code adjudicates.
          That division of labor is the thing we are trying to get right.
        </p>
      </section>

      <hr className="fp-divider" />

      <section className="fp-section">
        <h2 className="fp-section__heading">The End We Are Working Toward</h2>
        <p>
          The honest dream — and we will call it a dream because we are not there
          yet — is a referee that you can sit down with at any hour and trust.
          One that generates dungeons whose layouts make spatial sense, whose
          inhabitants have reasons, whose treasure was not invented to please you.
          One that runs a six-hour session and, at the end of it, the numbers on
          your character sheet still add up.
        </p>
        <p>
          When the AI side and the code side are both tight — when the model is
          doing only what it is genuinely good at, and the engine is doing the
          rest — we believe what falls out is the thing solo players have wanted
          for forty years. Interesting stories, generated freely. Real dungeons,
          built to be survived rather than enjoyed. Sessions that matter because
          the rules said they did.
        </p>
        <p>
          We are some distance from that. We are closer than we were last month.
        </p>
      </section>

      <hr className="fp-divider" />

      <section className="fp-section fp-section--closing">
        <p>
          If an unfinished, opinionated, occasionally broken tool — built by people
          who would rather show you the seams than hide them — sounds like
          something you would like to walk a few corridors with, we would be glad
          of the company.
        </p>
        <div className="fp-cta-wrap">
          <a href="/adventures/new" className="fp-cta-btn">
            Roll a Character
          </a>
        </div>
        <p className="fp-typewriter fp-closing-note">
          Expect rough edges. Expect to die.
          <br />
          Tell us where it broke; we will fix what we can.
        </p>
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
