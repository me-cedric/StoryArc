/*!
* StoryArc EPUB bundle: @readium/navigator and @readium/shared from readium/ts-toolkit.
* https://github.com/readium/ts-toolkit
*
* BSD 3-Clause License
*
* Copyright (c) 2022, Readium Foundation
*
* Redistribution and use in source and binary forms, with or without
* modification, are permitted provided that the following conditions are met:
*
* 1. Redistributions of source code must retain the above copyright notice, this
*    list of conditions and the following disclaimer.
*
* 2. Redistributions in binary form must reproduce the above copyright notice,
*    this list of conditions and the following disclaimer in the documentation
*    and/or other materials provided with the distribution.
*
* 3. Neither the name of the copyright holder nor the names of its
*    contributors may be used to endorse or promote products derived from
*    this software without specific prior written permission.
*
* THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
* AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
* IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
* DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
* FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
* DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
* SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
* CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
* OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
* OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/
var StoryArcEpub=(function(e){Object.defineProperty(e,Symbol.toStringTag,{value:`Module`});var t=Object.defineProperty,n=(e,t,n)=>()=>{if(n)throw n[0];try{return e&&(t=e(e=0)),t}catch(e){throw n=[e],e}},r=(e,n)=>{let r={};for(var i in e)t(r,i,{get:e[i],enumerable:!0});return n||t(r,Symbol.toStringTag,{value:`Module`}),r},i=class{close(){}links(){return[]}get(e){throw Error(`This is an empty fetcher`)}},a=class{constructor(e,t){this.client=e||window.fetch.bind(window),this.baseUrl=t}links(){return[]}get(e){let t=e.toURL(this.baseUrl);if(t===void 0)throw Error(`Invalid HREF: ${e.href}`);return new o(this.client,e,t)}close(){}},o=class{constructor(e,t,n){this.client=e||window.fetch.bind(window),this._link=t,this.url=n}async headResponse(){if(this._headResponse)return this._headResponse;let e=await this.client(this.url,{method:`HEAD`});if(!e.ok)throw Error(`http HEAD request for ${this.url} failed with HTTP status code ${e.status}`);return this._headResponse=e,e}close(){}async link(){return this._link}async read(e,t){if(e)throw Error(`http read range not implemented!`);let n=await this.client(this.url,t?.signal?{signal:t.signal}:void 0);if(!n.ok)throw Error(`http GET request for ${this.url} failed with HTTP status code ${n.status}`);return new Uint8Array(await n.arrayBuffer())}async length(){let e=(await this.headResponse()).headers.get(`content-length`);if(e===null||e===``)throw Error(`length for resource unavailable`);return parseInt(e)}async readAsJSON(){let e=await this.client(this.url);if(!e.ok)throw Error(`http GET request for ${this.url} failed with HTTP status code ${e.status}`);return await e.json()}async readAsString(){let e=await this.client(this.url);if(!e.ok)throw Error(`http GET request for ${this.url} failed with HTTP status code ${e.status}`);return await e.text()}async readAsXML(){let e=await this.client(this.url);if(!e.ok)throw Error(`http GET request for ${this.url} failed with HTTP status code ${e.status}`);return new DOMParser().parseFromString(await e.text(),this._link.mediaType.isHTML?this._link.mediaType.essence:`text/xml`)}},s=class{constructor(e,t){this.start=e,this.endInclusive=t}},c=class{readAsString(){return this.read().then(e=>e===void 0?e:new TextDecoder().decode(e))}readAsJSON(){return this.readAsString().then(e=>e===void 0?e:JSON.parse(e))}readAsXML(){return this.link().then(e=>this.readAsString().then(t=>t===void 0?t:new DOMParser().parseFromString(t,e.mediaType.isHTML?e.mediaType.essence:`text/xml`)))}};function l(e){return e&&Array.isArray(e)?e:void 0}function u(e){return e&&typeof e==`string`?[e]:l(e)}function d(e){return typeof e==`string`?new Date(e):void 0}function f(e){return isNaN(e)?void 0:e}function p(e){return f(e)!==void 0&&Math.sign(e)>=0?e:void 0}function m(e){let t=[];return e.forEach(e=>t.push(e)),t}var h=class e{constructor(e={}){this.conformsTo=e.conformsTo??[],this.certification=e.certification??null,this.summary=e.summary??null,this.accessMode=e.accessMode??[],this.accessModeSufficient=e.accessModeSufficient??[],this.feature=e.feature??[],this.hazard=e.hazard??[],this.exemption=e.exemption??[]}static deserialize(t){if(!t||typeof t!=`object`)return;let n=t,r=u(n.conformsTo),i=u(n.accessMode),a=l(n.accessModeSufficient),o=u(n.feature),s=u(n.hazard),c=u(n.exemption);return new e({conformsTo:r?r.map(e=>ee.deserialize(e)).filter(e=>e!==void 0):void 0,certification:n.certification?te.deserialize(n.certification):void 0,summary:n.summary,accessMode:i?i.map(e=>v.deserialize(e)).filter(e=>e!==void 0):void 0,accessModeSufficient:a?a.map(e=>ne.deserialize(e)).filter(e=>e!==void 0):void 0,feature:o?o.map(e=>x.deserialize(e)).filter(e=>e!==void 0):void 0,hazard:s?s.map(e=>C.deserialize(e)).filter(e=>e!==void 0):void 0,exemption:c?c.map(e=>re.deserialize(e)).filter(e=>e!==void 0):void 0})}serialize(){let e={};return this.conformsTo?.length>0&&(e.conformsTo=this.conformsTo.map(e=>e.serialize())),this.certification!==void 0&&this.certification!==null&&(e.certification=this.certification.serialize()),this.summary!==void 0&&this.summary!==null&&(e.summary=this.summary),this.accessMode?.length>0&&(e.accessMode=this.accessMode.map(e=>e.serialize())),this.accessModeSufficient?.length>0&&(e.accessModeSufficient=this.accessModeSufficient.map(e=>e.serialize())),this.feature?.length>0&&(e.feature=this.feature.map(e=>e.serialize())),this.hazard?.length>0&&(e.hazard=this.hazard.map(e=>e.serialize())),this.exemption?.length>0&&(e.exemption=this.exemption.map(e=>e.serialize())),e}},g=class e{constructor(e){this.uri=e}static deserialize(t){if(t&&typeof t==`string`)return new e(t)}serialize(){return this.uri}get isWCAGLevelA(){return this===e.EPUB_A11Y_10_WCAG_20_A||this===e.EPUB_A11Y_11_WCAG_20_A||this===e.EPUB_A11Y_11_WCAG_21_A||this===e.EPUB_A11Y_11_WCAG_22_A}get isWCAGLevelAA(){return this===e.EPUB_A11Y_10_WCAG_20_AA||this===e.EPUB_A11Y_11_WCAG_20_AA||this===e.EPUB_A11Y_11_WCAG_21_AA||this===e.EPUB_A11Y_11_WCAG_22_AA}get isWCAGLevelAAA(){return this===e.EPUB_A11Y_10_WCAG_20_AAA||this===e.EPUB_A11Y_11_WCAG_20_AAA||this===e.EPUB_A11Y_11_WCAG_21_AAA||this===e.EPUB_A11Y_11_WCAG_22_AAA}};g.EPUB_A11Y_10_WCAG_20_A=new g(`http://www.idpf.org/epub/a11y/accessibility-20170105.html#wcag-a`),g.EPUB_A11Y_10_WCAG_20_AA=new g(`http://www.idpf.org/epub/a11y/accessibility-20170105.html#wcag-aa`),g.EPUB_A11Y_10_WCAG_20_AAA=new g(`http://www.idpf.org/epub/a11y/accessibility-20170105.html#wcag-aaa`),g.EPUB_A11Y_11_WCAG_20_A=new g(`https://www.w3.org/TR/epub-a11y-11#wcag-2.0-a`),g.EPUB_A11Y_11_WCAG_20_AA=new g(`https://www.w3.org/TR/epub-a11y-11#wcag-2.0-aa`),g.EPUB_A11Y_11_WCAG_20_AAA=new g(`https://www.w3.org/TR/epub-a11y-11#wcag-2.0-aaa`),g.EPUB_A11Y_11_WCAG_21_A=new g(`https://www.w3.org/TR/epub-a11y-11#wcag-2.1-a`),g.EPUB_A11Y_11_WCAG_21_AA=new g(`https://www.w3.org/TR/epub-a11y-11#wcag-2.1-aa`),g.EPUB_A11Y_11_WCAG_21_AAA=new g(`https://www.w3.org/TR/epub-a11y-11#wcag-2.1-aaa`),g.EPUB_A11Y_11_WCAG_22_A=new g(`https://www.w3.org/TR/epub-a11y-11#wcag-2.2-a`),g.EPUB_A11Y_11_WCAG_22_AA=new g(`https://www.w3.org/TR/epub-a11y-11#wcag-2.2-aa`),g.EPUB_A11Y_11_WCAG_22_AAA=new g(`https://www.w3.org/TR/epub-a11y-11#wcag-2.2-aaa`);var ee=g,te=class e{constructor(e=null,t=null,n=null){this.certifiedBy=e,this.credential=t,this.report=n}static deserialize(t){if(t&&typeof t==`object`)return new e(t.certifiedBy,t.credential,t.report)}serialize(){let e={};return this.certifiedBy&&(e.certifiedBy=this.certifiedBy),this.credential&&(e.credential=this.credential),this.report&&(e.report=this.report),e}},_=class e{constructor(e){this.value=e}static deserialize(t){if(t&&typeof t==`string`)return new e(t)}serialize(){return this.value}};_.AUDITORY=new _(`auditory`),_.CHART_ON_VISUAL=new _(`chartOnVisual`),_.CHEM_ON_VISUAL=new _(`chemOnVisual`),_.COLOR_DEPENDENT=new _(`colorDependent`),_.DIAGRAM_ON_VISUAL=new _(`diagramOnVisual`),_.MATH_ON_VISUAL=new _(`mathOnVisual`),_.MUSIC_ON_VISUAL=new _(`musicOnVisual`),_.TACTILE=new _(`tactile`),_.TEXT_ON_VISUAL=new _(`textOnVisual`),_.TEXTUAL=new _(`textual`),_.VISUAL=new _(`visual`);var v=_,y=class e{constructor(t){if(typeof t==`string`){if(!e.VALID_MODES.has(t.toLowerCase()))return;this.value=t.toLowerCase()}else{let n=t.filter(t=>e.VALID_MODES.has(t.toLowerCase()));if(n.length===0)return;this.value=Array.from(new Set(n))}}static deserialize(t){if(!t)return;if(typeof t==`string`)return e.VALID_MODES.has(t.toLowerCase())?new e(t):void 0;if(!Array.isArray(t))return;let n=t.filter(t=>t?e.VALID_MODES.has(t.toLowerCase()):!1);if(n.length!==0)return new e(n)}serialize(){return this.value}};y.VALID_MODES=new Set([`auditory`,`tactile`,`textual`,`visual`]),y.AUDITORY=new y(`auditory`),y.TACTILE=new y(`tactile`),y.TEXTUAL=new y(`textual`),y.VISUAL=new y(`visual`);var ne=y,b=class e{constructor(e){this.value=e}static deserialize(t){if(t&&typeof t==`string`)return new e(t)}serialize(){return this.value}};b.NONE=new b(`none`),b.ANNOTATIONS=new b(`annotations`),b.ARIA=new b(`ARIA`),b.INDEX=new b(`index`),b.PAGE_BREAK_MARKERS=new b(`pageBreakMarkers`),b.PAGE_NAVIGATION=new b(`pageNavigation`),b.PRINT_PAGE_NUMBERS=new b(`printPageNumbers`),b.READING_ORDER=new b(`readingOrder`),b.STRUCTURAL_NAVIGATION=new b(`structuralNavigation`),b.TABLE_OF_CONTENTS=new b(`tableOfContents`),b.TAGGED_PDF=new b(`taggedPDF`),b.ALTERNATIVE_TEXT=new b(`alternativeText`),b.AUDIO_DESCRIPTION=new b(`audioDescription`),b.CAPTIONS=new b(`captions`),b.CLOSED_CAPTIONS=new b(`closedCaptions`),b.DESCRIBED_MATH=new b(`describedMath`),b.LONG_DESCRIPTION=new b(`longDescription`),b.OPEN_CAPTIONS=new b(`openCaptions`),b.SIGN_LANGUAGE=new b(`signLanguage`),b.TRANSCRIPT=new b(`transcript`),b.DISPLAY_TRANSFORMABILITY=new b(`displayTransformability`),b.SYNCHRONIZED_AUDIO_TEXT=new b(`synchronizedAudioText`),b.TIMING_CONTROL=new b(`timingControl`),b.UNLOCKED=new b(`unlocked`),b.CHEM_ML=new b(`ChemML`),b.LATEX=new b(`latex`),b.LATEX_CHEMISTRY=new b(`latex-chemistry`),b.MATH_ML=new b(`MathML`),b.MATH_ML_CHEMISTRY=new b(`MathML-chemistry`),b.TTS_MARKUP=new b(`ttsMarkup`),b.HIGH_CONTRAST_AUDIO=new b(`highContrastAudio`),b.HIGH_CONTRAST_DISPLAY=new b(`highContrastDisplay`),b.LARGE_PRINT=new b(`largePrint`),b.BRAILLE=new b(`braille`),b.TACTILE_GRAPHIC=new b(`tactileGraphic`),b.TACTILE_OBJECT=new b(`tactileObject`),b.FULL_RUBY_ANNOTATIONS=new b(`fullRubyAnnotations`),b.HORIZONTAL_WRITING=new b(`horizontalWriting`),b.RUBY_ANNOTATIONS=new b(`rubyAnnotations`),b.VERTICAL_WRITING=new b(`verticalWriting`),b.WITH_ADDITIONAL_WORD_SEGMENTATION=new b(`withAdditionalWordSegmentation`),b.WITHOUT_ADDITIONAL_WORD_SEGMENTATION=new b(`withoutAdditionalWordSegmentation`);var x=b,S=class e{constructor(e){this.value=e}static deserialize(t){if(t&&typeof t==`string`)return new e(t)}serialize(){return this.value}};S.FLASHING=new S(`flashing`),S.NO_FLASHING_HAZARD=new S(`noFlashingHazard`),S.UNKNOWN_FLASHING_HAZARD=new S(`unknownFlashingHazard`),S.MOTION_SIMULATION=new S(`motionSimulation`),S.NO_MOTION_SIMULATION_HAZARD=new S(`noMotionSimulationHazard`),S.UNKNOWN_MOTION_SIMULATION_HAZARD=new S(`unknownMotionSimulationHazard`),S.SOUND=new S(`sound`),S.NO_SOUND_HAZARD=new S(`noSoundHazard`),S.UNKNOWN_SOUND_HAZARD=new S(`unknownSoundHazard`),S.UNKNOWN=new S(`unknown`),S.NONE=new S(`none`);var C=S,w=class e{constructor(e){this.value=e}static deserialize(t){if(t&&typeof t==`string`)return new e(t)}serialize(){return this.value}};w.NONE=new w(`none`),w.DOCUMENTED=new w(`documented`),w.LEGAL=new w(`legal`),w.TEMPORARY=new w(`temporary`),w.TECHNICAL=new w(`technical`),w.EAA_DISPROPORTIONATE_BURDEN=new w(`eaa-disproportionate-burden`),w.EAA_FUNDAMENTAL_ALTERATION=new w(`eaa-fundamental-alteration`),w.EAA_MICROENTERPRISE=new w(`eaa-microenterprise`),w.EAA_TECHNICAL_IMPOSSIBILITY=new w(`eaa-technical-impossibility`),w.EAA_TEMPORARY=new w(`eaa-temporary`);var re=w,ie=`modulepreload`,ae=function(e){return`/`+e},oe={},T=function(e,t,n){let r=Promise.resolve();if(t&&t.length>0){let e=function(e){return Promise.all(e.map(e=>Promise.resolve(e).then(e=>({status:`fulfilled`,value:e}),e=>({status:`rejected`,reason:e}))))};document.getElementsByTagName(`link`);let n=document.querySelector(`meta[property=csp-nonce]`),i=n?.nonce||n?.getAttribute(`nonce`);r=e(t.map(e=>{if(e=ae(e),e in oe)return;oe[e]=!0;let t=e.endsWith(`.css`),n=t?`[rel="stylesheet"]`:``;if(document.querySelector(`link[href="${e}"]${n}`))return;let r=document.createElement(`link`);if(r.rel=t?`stylesheet`:ie,t||(r.as=`script`),r.crossOrigin=``,r.href=e,i&&r.setAttribute(`nonce`,i),document.head.appendChild(r),t)return new Promise((t,n)=>{r.addEventListener(`load`,t),r.addEventListener(`error`,()=>n(Error(`Unable to preload CSS for ${e}`)))})}))}function i(e){let t=new Event(`vite:preloadError`,{cancelable:!0});if(t.payload=e,window.dispatchEvent(t),!t.defaultPrevented)throw e}return r.then(t=>{for(let e of t||[])e.status===`rejected`&&i(e.reason);return e().catch(i)})},se=[`en`,`ar`,`da`,`el`,`es`,`et`,`fi`,`fr`,`it`,`pl`,`pt_PT`,`sv`],ce={publication:JSON.parse(`{"format":{"audiobook":"Audiobook","audiobookJSON":"Audiobook Manifest","cbz":"Comic Book Archive","divina":"Divina Publication","divinaJSON":"Divina Publication Manifest","epub":"EPUB","lcpa":"LCP Protected Audiobook","lcpdf":"LCP Protected PDF","lcpl":"LCP License Document","pdf":"PDF","rwp":"Readium Web Publication","rwpm":"Readium Web Publication Manifest","zab":"Audiobook Archive","zip":"ZIP Archive"},"kind":{"audiobook_one":"audiobook","audiobook_other":"audiobooks","book_one":"book","book_other":"books","comic_one":"comic","comic_other":"comics","document_one":"document","document_other":"documents"},"metadata":{"accessibility":{"display-guide":{"accessibility-summary":{"no-metadata":"No information is available","publisher-contact":"For more information about the accessibility of this product, please contact the publisher: ","title":"Accessibility summary"},"additional-accessibility-information":{"aria":{"compact":"ARIA roles included","descriptive":"Content is enhanced with ARIA roles to optimize organization and facilitate navigation"},"audio-descriptions":"Audio descriptions","braille":"Braille","color-not-sole-means-of-conveying-information":"Color is not the sole means of conveying information","dyslexia-readability":"Dyslexia readability","full-ruby-annotations":"Full ruby annotations","high-contrast-between-foreground-and-background-audio":"High contrast between foreground and background audio","high-contrast-between-text-and-background":"High contrast between foreground text and background","large-print":"Large print","page-breaks":{"compact":"Page breaks included","descriptive":"Page breaks included from the original print source"},"ruby-annotations":"Some Ruby annotations","sign-language":"Sign language","tactile-graphics":{"compact":"Tactile graphics included","descriptive":"Tactile graphics have been integrated to facilitate access to visual elements for blind people"},"tactile-objects":"Tactile 3D objects","text-to-speech-hinting":"Text-to-speech hinting provided","title":"Additional accessibility information","ultra-high-contrast-between-text-and-background":"Ultra high contrast between text and background","visible-page-numbering":"Visible page numbering","without-background-sounds":"Without background sounds"},"conformance":{"a":{"compact":"This publication meets minimum accessibility standards","descriptive":"The publication contains a conformance statement that it meets the EPUB Accessibility and WCAG 2 Level A standard"},"aa":{"compact":"This publication meets accepted accessibility standards","descriptive":"The publication contains a conformance statement that it meets the EPUB Accessibility and WCAG 2 Level AA standard"},"aaa":{"compact":"This publication exceeds accepted accessibility standards","descriptive":"The publication contains a conformance statement that it meets the EPUB Accessibility and WCAG 2 Level AAA standard"},"certifier":"The publication was certified by ","certifier-credentials":"The certifier's credential is ","details":{"certification-info":"The publication was certified on ","certifier-report":"For more information refer to the certifier's report","claim":"This publication claims to meet","epub-accessibility-1-0":"EPUB Accessibility 1.0","epub-accessibility-1-1":"EPUB Accessibility 1.1","level-a":"Level A","level-aa":"Level AA","level-aaa":"Level AAA","wcag-2-0":{"compact":"WCAG 2.0","descriptive":"Web Content Accessibility Guidelines (WCAG) 2.0"},"wcag-2-1":{"compact":"WCAG 2.1","descriptive":"Web Content Accessibility Guidelines (WCAG) 2.1"},"wcag-2-2":{"compact":"WCAG 2.2","descriptive":"Web Content Accessibility Guidelines (WCAG) 2.2"}},"details-title":"Detailed conformance information","no":"No information is available","title":"Conformance","unknown-standard":"Conformance to accepted standards for accessibility of this publication cannot be determined"},"hazards":{"flashing":{"compact":"Flashing content","descriptive":"The publication contains flashing content that can cause photosensitive seizures"},"flashing-none":{"compact":"No flashing hazards","descriptive":"The publication does not contain flashing content that can cause photosensitive seizures"},"flashing-unknown":{"compact":"Flashing hazards not known","descriptive":"The presence of flashing content that can cause photosensitive seizures could not be determined"},"motion":{"compact":"Motion simulation","descriptive":"The publication contains motion simulations that can cause motion sickness"},"motion-none":{"compact":"No motion simulation hazards","descriptive":"The publication does not contain motion simulations that can cause motion sickness"},"motion-unknown":{"compact":"Motion simulation hazards not known","descriptive":"The presence of motion simulations that can cause motion sickness could not be determined"},"no-metadata":"No information is available","none":{"compact":"No hazards","descriptive":"The publication contains no hazards"},"sound":{"compact":"Sounds","descriptive":"The publication contains sounds that can cause sensitivity issues"},"sound-none":{"compact":"No sound hazards","descriptive":"The publication does not contain sounds that can cause sensitivity issues"},"sound-unknown":{"compact":"Sound hazards not known","descriptive":"The presence of sounds that can cause sensitivity issues could not be determined"},"title":"Hazards","unknown":"The presence of hazards is unknown"},"legal-considerations":{"exempt":{"compact":"Claims an accessibility exemption in some jurisdictions","descriptive":"This publication claims an accessibility exemption in some jurisdictions"},"no-metadata":"No information is available","title":"Legal considerations"},"navigation":{"index":{"compact":"Index","descriptive":"Index with links to referenced entries"},"no-metadata":"No information is available","page-navigation":{"compact":"Go to page","descriptive":"Page list to go to pages from the print source version"},"structural":{"compact":"Headings","descriptive":"Elements such as headings, tables, etc for structured navigation"},"title":"Navigation","toc":{"compact":"Table of contents","descriptive":"Table of contents to all chapters of the text via links"}},"rich-content":{"accessible-chemistry-as-latex":{"compact":"Chemical formulas in LaTeX","descriptive":"Chemical formulas in accessible format (LaTeX)"},"accessible-chemistry-as-mathml":{"compact":"Chemical formulas in MathML","descriptive":"Chemical formulas in accessible format (MathML)"},"accessible-math-as-latex":{"compact":"Math as LaTeX","descriptive":"Math formulas in accessible format (LaTeX)"},"accessible-math-described":"Text descriptions of math are provided","closed-captions":{"compact":"Videos have closed captions","descriptive":"Videos included in publications have closed captions"},"extended-descriptions":"Information-rich images are described by extended descriptions","math-as-mathml":{"compact":"Math as MathML","descriptive":"Math formulas in accessible format (MathML)"},"open-captions":{"compact":"Videos have open captions","descriptive":"Videos included in publications have open captions"},"title":"Rich content","transcript":"Transcript(s) provided","unknown":"No information is available"},"ways-of-reading":{"nonvisual-reading":{"alt-text":{"compact":"Has alternative text","descriptive":"Has alternative text descriptions for images"},"no-metadata":"No information about nonvisual reading is available","none":{"compact":"Not readable in read aloud or dynamic braille","descriptive":"The content is not readable as read aloud speech or dynamic braille"},"not-fully":{"compact":"Not fully readable in read aloud or dynamic braille","descriptive":"Not all of the content will be readable as read aloud speech or dynamic braille"},"readable":{"compact":"Readable in read aloud or dynamic braille","descriptive":"All content can be read as read aloud speech or dynamic braille"}},"prerecorded-audio":{"complementary":{"compact":"Prerecorded audio clips","descriptive":"Prerecorded audio clips are embedded in the content"},"no-metadata":"No information about prerecorded audio is available","only":{"compact":"Prerecorded audio only","descriptive":"Audiobook with no text alternative"},"synchronized":{"compact":"Prerecorded audio synchronized with text","descriptive":"All the content is available as prerecorded audio synchronized with text"}},"title":"Ways of reading","visual-adjustments":{"modifiable":{"compact":"Appearance can be modified","descriptive":"Appearance of the text and page layout can be modified according to the capabilities of the reading system (font family and font size, spaces between paragraphs, sentences, words, and letters, as well as color of background and text)"},"unknown":"No information about appearance modifiability is available","unmodifiable":{"compact":"Appearance cannot be modified","descriptive":"Text and page layout cannot be modified as the reading experience is close to a print version, but reading systems can still provide zooming options"}}}}},"altIdentifier_one":"alternate identifier","altIdentifier_other":"alternate identifiers","artist_one":"artist","artist_other":"artists","author_one":"author","author_other":"authors","collection_one":"editorial collection","collection_other":"editorial collections","colorist_one":"colorist","colorist_other":"colorists","contributor_one":"contributor","contributor_other":"contributors","description":"description","duration":"duration","editor_one":"editor","editor_other":"editors","identifier_one":"identifier","identifier_other":"identifiers","illustrator_one":"illustrator","illustrator_other":"illustrators","imprint_one":"imprint","imprint_other":"imprints","inker_one":"inker","inker_other":"inkers","language_one":"language","language_other":"languages","letterer_one":"letterer","letterer_other":"letterers","modified":"modification date","narrator_one":"narrator","narrator_other":"narrators","numberOfPages":"print length","penciler_one":"penciler","penciler_other":"pencilers","published":"publication date","publisher_one":"publisher","publisher_other":"publishers","series_one":"series","series_other":"series","subject_one":"subject","subject_other":"subjects","subtitle":"subtitle","title":"title","translator_one":"translator","translator_other":"translators"}}`)},le=r({default:()=>de,publication:()=>ue}),ue,de,fe=n((()=>{ue=JSON.parse(`{"format":{"audiobook":"كتاب صوتي","audiobookJSON":"ملف تعريف الكتاب الصوتي","cbz":"أرشيف الكتب المصورة","divina":"منشور Divina","divinaJSON":"ملف تعريفي لمنشور Divina","epub":"EPUB","lcpa":"كتاب صوتي محمي بـLCP","lcpdf":"PDF محمي بـLCP","lcpl":"مستند ترخيص LCP","pdf":"PDF","rwp":"منشور Readium Web","rwpm":"ملف تعريفي لمنشور Readium Publication","zab":"أرشيف الكتب الصوتية","zip":"أرشيف ملفات ZIP"},"kind":{"audiobook_few":"كتب صوتية","audiobook_many":"كتاب صوتي","audiobook_one":"كتاب صوتي واحد","audiobook_other":"كتاب صوتي","audiobook_two":"كتابان صوتيان","audiobook_zero":"لا يوجد كتب صوتية","book_few":"كتب","book_many":"كتاب","book_one":"كتاب واحد","book_other":"كتاب","book_two":"كتابان","book_zero":"لا يوجد كتب","comic_few":"كتب مصورة","comic_many":"كتاب مصور","comic_one":"كتاب مصور واحد","comic_other":"كتاب مصور","comic_two":"كتابان مصوران","comic_zero":"لا يوجد كتب مصورة","document_few":"مستندات","document_many":"مستند","document_one":"مستند واحد","document_other":"مستند","document_two":"مستندان","document_zero":"لا يوجد مستندات"},"metadata":{"accessibility":{"display-guide":{"accessibility-summary":{"no-metadata":"لا تتوفر أي معلومات","publisher-contact":"لمزيد من المعلومات حول إمكانية الوصول إلى هذا المنتج، يُرجى التواصل مع الناشر: ","title":"ملخص إمكانية الوصول"},"additional-accessibility-information":{"aria":{"compact":"أدوار ARIA مدرَجة","descriptive":"يتم تعزيز المحتوى باستخدام أدوار ARIA لتحسين التنظيم وتيسير التنقّل"},"audio-descriptions":"الوصف الصوتي","braille":"برايل","color-not-sole-means-of-conveying-information":"اللون ليس الوسيلة الوحيدة لنقل المعلومات","dyslexia-readability":"سهولة القراءة لذوي عُسر القراءة","full-ruby-annotations":"شروح روبي كاملة","high-contrast-between-foreground-and-background-audio":"تباين عالٍ بين الصوت الرئيسي وصوت الخلفية","high-contrast-between-text-and-background":"تباين عالٍ بين النص والخلفية","large-print":"خط كبير","page-breaks":{"compact":"فواصل الصفحات متضمَّنة","descriptive":"فواصل الصفحات متضمَّنة من المصدر المطبوع الأصلي"},"ruby-annotations":"بعض شروح الروبي","sign-language":"لغة الإشارة","tactile-graphics":{"compact":"الرسوم اللمسية مدرجة","descriptive":"تم دمج الرسوم اللمسية لتيسير الوصول إلى العناصر البصرية للأشخاص المكفوفين"},"tactile-objects":"مجسمات لمسية ثلاثية الأبعاد","text-to-speech-hinting":"إرشادات تحويل النص إلى كلام (TTS)متوفرة","title":"معلومات إضافية عن إمكانية الوصول","ultra-high-contrast-between-text-and-background":"تباين عالٍ جدًا بين النص والخلفية","visible-page-numbering":"ترقيم صفحات مرئي","without-background-sounds":"من دون أصوات في خلفية"},"conformance":{"a":{"compact":"هذا المنشور يفي بالمعايير الدنيا لإمكانية الوصول","descriptive":"يحتوي هذا المنشور على بيان مطابقة يفيد بأنه يفي بمعيار إمكانية الوصول في EPUB وبمستوى A من معيار WCAG 2"},"aa":{"compact":"هذا المنشور يفي بالمعايير المعتمدة لإمكانية الوصول","descriptive":"يحتوي هذا المنشور على بيان مطابقة يفيد بأنه يفي بمعيار إمكانية الوصول في EPUB وبمستوى AA من معيار WCAG 2"},"aaa":{"compact":"هذا المنشور يفوق المعايير المقبولة لإمكانية الوصول","descriptive":"يحتوي هذا المنشور على بيان مطابقة يفيد بأنه يفي بمعيار إمكانية الوصول في EPUB وبمستوى AAA من معيار WCAG 2"},"certifier":"تم اعتماد هذا المنشور من قبل ","certifier-credentials":"بيانات اعتماد جهة التصديق ","details":{"certification-info":"تم اعتماد هذا المنشور في تاريخ ","certifier-report":"لمزيد من المعلومات، يرجى الرجوع إلى تقرير جهة التصديق","claim":"يدّعي هذا المنشور أنه يستوفي","epub-accessibility-1-0":"معيار إمكانية الوصول لـ EPUB إصدار 1.0","epub-accessibility-1-1":"معيار إمكانية الوصول لـ EPUB إصدار 1.1","level-a":"المستوى A","level-aa":"المستوى AA","level-aaa":"المستوى AAA","wcag-2-0":{"compact":"WCAG 2.0","descriptive":"مبادئ النفاذ إلى محتوى الويب (WCAG) 2.0"},"wcag-2-1":{"compact":"WCAG 2.1","descriptive":"مبادئ النفاذ إلى محتوى الويب (WCAG) 2.1"},"wcag-2-2":{"compact":"WCAG 2.2","descriptive":"مبادئ النفاذ إلى محتوى الويب (WCAG) 2.2"}},"details-title":"معلومات تفصيلية عن مدى المطابقة","no":"لا تتوفر أي معلومات","title":"المطابقة","unknown-standard":"لا يمكن التأكد من مدى مطابقة هذا المنشور للمعايير المقبولة لإمكانية الوصول"},"hazards":{"flashing":{"compact":"محتوى وامض","descriptive":"يحتوي هذا المنشور على محتوى وامض قد يسبب نوبات حساسة للضوء"},"flashing-none":{"compact":"لا توجد مخاطر وميض","descriptive":"لا يحتوي هذا المنشور على محتوى وامض قد يسبب نوبات حساسة للضوء"},"flashing-unknown":{"compact":"مخاطر الوميض غير معروفة","descriptive":"لم يُمكن التأكد من وجود محتوى وامض قد يسبب نوبات حساسية للضوء"},"motion":{"compact":"محاكاة الحركة","descriptive":"يحتوي المنشور على محاكاة حركة قد تسبّب دوار الحركة"},"motion-none":{"compact":"لا توجد مخاطر محاكاة الحركة","descriptive":"لا يحتوي المنشور على محاكاة حركة قد تسبّب دوار الحركة"},"motion-unknown":{"compact":"مخاطر محاكاة الحركة غير معروفة","descriptive":"تعذّر تحديد ما إذا كانت هناك محاكاة للحركة قد تُسبب دوار الحركة"},"no-metadata":"لا تتوفر أي معلومات","none":{"compact":"لا توجد مخاطر","descriptive":"لا يحتوي المنشور على أي مخاطر"},"sound":{"compact":"أصوات","descriptive":"يحتوي المنشور على أصوات قد تؤدي إلى مشاكل حساسية صوتية"},"sound-none":{"compact":"لا توجد مخاطر صوتية","descriptive":"لا يحتوي المنشور على أصوات قد تؤدي إلى مشاكل حساسية صوتية"},"sound-unknown":{"compact":"مخاطر الصوت غير معروفة","descriptive":"تعذّر تحديد ما إذا كانت هناك أصوات قد تُسبب مشكلات في الحساسية"},"title":"مخاطر","unknown":"وجود المخاطر غير معروف"},"legal-considerations":{"exempt":{"compact":"يُعلن عن استثناء من متطلبات إمكانية الوصول من بعض السلطات القضائية","descriptive":"يُصرّح هذا المنشور بوجود استثناء من متطلبات إمكانية الوصول من بعض السلطات القضائية"},"no-metadata":"لا تتوفر أي معلومات","title":"اعتبارات قانونية"},"navigation":{"index":{"compact":"كشاف","descriptive":"كشاف يحتوي على روابط إلى الإدخالات المشار إليها"},"no-metadata":"لا تتوفر أي معلومات","page-navigation":{"compact":"الانتقال إلى صفحة","descriptive":"قائمة الصفحات للانتقال إلى صفحات من النسخة المطبوعة الأصلية"},"structural":{"compact":"العناوين","descriptive":"عناصر مثل العناوين والجداول وغيرها للتنقل المنظّم"},"title":"التنقل","toc":{"compact":"جدول المحتويات","descriptive":"جدول المحتويات لكل فصول النص عبر روابط"}},"rich-content":{"accessible-chemistry-as-latex":{"compact":"الصيغ الكيميائية بصيغة LaTeX","descriptive":"الصيغ الكيميائية بشكل ميسر (LaTeX)"},"accessible-chemistry-as-mathml":{"compact":"الصيغ الكيميائية بصيغة MathML","descriptive":"الصيغ الكيميائية بشكل ميسر (MathML)"},"accessible-math-as-latex":{"compact":"الرياضيات بصيغة LaTeX","descriptive":"الصيغ الرياضية بشكل ميسر (LaTeX)"},"accessible-math-described":"تتوفر أوصاف نصية للصيغ الرياضية","closed-captions":{"compact":"تحتوي الفيديوهات على شروح مغلقة","descriptive":"الفيديوهات الموجودة في المنشورات تحتوي على شروح مغلقة"},"extended-descriptions":"يتم وصف الصور الغنية بالمعلومات بأوصاف مفصّلة","math-as-mathml":{"compact":"الرياضيات بصيغة MathML","descriptive":"الصيغ الرياضية بشكل ميسر(MathML)"},"open-captions":{"compact":"تحتوي الفيديوهات على شروح مدمجة","descriptive":"الفيديوهات الموجودة في المنشورات تحتوي على شروح مدمجة"},"title":"محتوى غني","transcript":"يتوفر نص(نصوص)","unknown":"لا تتوفر أي معلومات"},"ways-of-reading":{"nonvisual-reading":{"alt-text":{"compact":"يحتوي على نص بديل","descriptive":"يحتوي على أوصاف نصية بديلة للصور"},"no-metadata":"لا تتوفر معلومات عن القراءة غير البصرية","none":{"compact":"غير قابل للقراءة بصوتٍ عالٍ أو بطريقة برايل الديناميكية","descriptive":"المحتوى غير قابل للقراءة بصوتٍ عالٍ أو بطريقة برايل الديناميكية"},"not-fully":{"compact":"غير قابل للقراءة بالكامل بصوتٍ عالٍ أو بطريقة برايل الديناميكية","descriptive":"لن يكون كل المحتوى قابلًا للقراءة بصوتٍ عالٍ أو بطريقة برايل الديناميكية"},"readable":{"compact":"قابل للقراءة بصوتٍ عالٍ أو بطريقة برايل الديناميكية","descriptive":"يمكن قراءة كل المحتوى بصوتٍ عالٍ أو بطريقة برايل الديناميكية"}},"prerecorded-audio":{"complementary":{"compact":"مقاطع الصوت المسجّلة مسبقًا","descriptive":"مقاطع الصوت المسجّلة مسبقًا مدمجة في المحتوى"},"no-metadata":"لا توجد معلومات عن الصوت المسجّل مسبقًا","only":{"compact":"الصوت المسجّل مسبقًا فقط","descriptive":"كتاب صوتي بدون بديل نصي"},"synchronized":{"compact":"صوت مسجّل مسبقًا متزامن مع النص","descriptive":"كل المحتوى متوفر كصوت مسجّل مسبقًا متزامن مع النص"}},"title":"طرق القراءة","visual-adjustments":{"modifiable":{"compact":"يمكن تعديل المظهر","descriptive":"يمكن تعديل مظهر النص وتخطيط الصفحة وفقاً لإمكانات نظام القراءة (اسم الخط وحجمه، والمسافات بين الفقرات والجمل والكلمات والأحرف، بالإضافة إلى لون الخلفية والنص)"},"unknown":"لا توجد معلومات عن إمكانية تعديل المظهر","unmodifiable":{"compact":"لا يمكن تعديل المظهر","descriptive":"لا يمكن تعديل مظهر النص وتخطيط الصفحات لأن تجربة القراءة قريبة من النسخة المطبوعة، ولكن تطبيقات القراءة ما زالت تتيح خيارات التكبير"}}}}},"altIdentifier_few":"رموز تعريفية بديلة","altIdentifier_many":"رمز تعريفي بديل","altIdentifier_one":"رمز تعريفي بديل واحد","altIdentifier_other":"رمز تعريفي بديل","altIdentifier_two":"رمزان تعريفيان بديلان","altIdentifier_zero":"لا يوجد رموز تعريفية بديلة","artist_few":"فنانون","artist_many":"فنان","artist_one":"فنان","artist_other":"فنانون","artist_two":"فنانان","artist_zero":"لا يوجد فنانون","author_few":"مؤلفون","author_many":"مؤلف","author_one":"مؤلف واحد","author_other":"مؤلفون","author_two":"مؤلفان","author_zero":"لا يوجد مؤلفون","collection_few":"سلاسل تحريرية","collection_many":"سلسلة تحريرية","collection_one":"سلسلة تحريرية","collection_other":"سلاسل تحريرية","collection_two":"سلسلتان تحريريتان","collection_zero":"لا يوجد أي سلسلة تحريرية","colorist_few":"ملوّنو الألوان","colorist_many":"ملون ألوان","colorist_one":"ملوّن الألوان","colorist_other":"ملوّنو الألوان","colorist_two":"ملونان ألوان","colorist_zero":"لا يوجد ملونو ألوان","contributor_few":"مساهمون","contributor_many":"مساهم","contributor_one":"مساهم","contributor_other":"مساهمون","contributor_two":"مساهمان","contributor_zero":"لا يوجد مساهمون","description":"وصف","duration":"مدة","editor_few":"محررون","editor_many":"محرر","editor_one":"محرر","editor_other":"محررون","editor_two":"محرران","editor_zero":"لا يوجد محررون","identifier_few":"رموز تعريفية","identifier_many":"رمز تعريفي","identifier_one":"رمز تعريفي","identifier_other":"رموز تعريفية","identifier_two":"رمزان تعريفيان","identifier_zero":"لا يوجد رموز تعريفية","illustrator_few":"رسّامون","illustrator_many":"رسّام","illustrator_one":"رسّام","illustrator_other":"رسامون","illustrator_two":"رسّامان","illustrator_zero":"لا يوجد رسّ امون","imprint_few":"علامات تجارية","imprint_many":"علامة تجارية","imprint_one":"العلامة التجارية للنشر","imprint_other":"العلامات التجارية للنشر","imprint_two":"علامتان تجاريتان","imprint_zero":"لا يوجد علامات تجارية","inker_few":"مُحَبِّرون","inker_many":"مُحَبّر","inker_one":"مُحَبِّر","inker_other":"مُحَبِّرون","inker_two":"مُحبّران","inker_zero":"لا يوجد مُحَبِّرون","language_few":"لغات","language_many":"لغة","language_one":"لغة","language_other":"لغة","language_two":"لغتان","language_zero":"لا يوجد لغات","letterer_few":"خطّاطون","letterer_many":"خطّاط","letterer_one":"خطّاط","letterer_other":"خطّاطون","letterer_two":"خطّاطان","letterer_zero":"لا يوجد خطّاطون","modified":"تاريخ التعديل","narrator_few":"قراء صوتيون","narrator_many":"قارئ صوتي","narrator_one":"قارئ صوتي","narrator_other":"قرّاء صوتيون","narrator_two":"قارئان صوتيان","narrator_zero":"لا يوجد قرّاء صوتيون","numberOfPages":"عدد الصفحات في النسخة المطبوعة","penciler_few":"رسّامون أوّليون","penciler_many":"رسّام أولي","penciler_one":"رسّام أولي","penciler_other":"رسّامون أوّليون","penciler_two":"رسامان أوّليان","penciler_zero":"لا يوجد رسّامون أوّليون","published":"تاريخ النشر","publisher_few":"ناشرون","publisher_many":"ناشر","publisher_one":"ناشر","publisher_other":"ناشرون","publisher_two":"ناشران","publisher_zero":"لا يوجد ناشرون","series_few":"سلاسل","series_many":"سلسلة","series_one":"سلسلة","series_other":"سلاسل","series_two":"سلسلتان","series_zero":"لا يوجد سلاسل","subject_few":"مواضيع","subject_many":"موضوع","subject_one":"موضوع","subject_other":"مواضيع","subject_two":"موضوعان","subject_zero":"لا يوجد مواضيع","subtitle":"عنوان فرعي","title":"العنوان","translator_few":"مترجمون","translator_many":"مترجم","translator_one":"مترجم","translator_other":"مترجمون","translator_two":"مترجمان","translator_zero":"لا يوجد مترجمون"}}`),de={publication:ue}})),pe=r({default:()=>he,publication:()=>me}),me,he,ge=n((()=>{me=JSON.parse(`{"format":{"audiobook":"Lydbog","audiobookJSON":"Lydbogs manifest","cbz":"Tegneserie (CBZ-arkiv)","divina":"Divina bog","divinaJSON":"Divina manifest","epub":"EPUB","lcpa":"LCP-beskyttet lydbog","lcpdf":"LCP-beskyttet PDF","lcpl":"LCP-licensdokument","pdf":"PDF","rwp":"Readium Web bog","rwpm":"Readium Web manifest","zab":"Lydbog (arkiv)","zip":"ZIP-arkiv"},"kind":{"audiobook_one":"lydbog","audiobook_other":"lydbøger","book_one":"bog","book_other":"bøger","comic_one":"tegneserie","comic_other":"tegneserier","document_one":"dokument","document_other":"dokumenter"},"metadata":{"accessibility":{"display-guide":{"accessibility-summary":{"no-metadata":"Ingen information tilgængelig","publisher-contact":"For mere information om tilgængeligheden af denne bog, kontakt venligst udgiveren: ","title":"Tilgængeligheds-oversigt"},"additional-accessibility-information":{"aria":{"compact":"Indeholder ARIA roller","descriptive":"Indhold forbedres med ARIA-roller for at optimere organisering og gøre navigation lettere"},"audio-descriptions":"Lydbeskrivelser","braille":"Punktskrift (braille)","color-not-sole-means-of-conveying-information":"Information gives ikke udelukkende via farver","dyslexia-readability":"Læsbarhed for ordblinde","full-ruby-annotations":"Indeholder såkalde \\"ruby\\" notationer (til asiatiske sprog)","high-contrast-between-foreground-and-background-audio":"Høj kontrast imellem forgrunds- og baggrunds-lyd","high-contrast-between-text-and-background":"Høj kontrast imellem tekst og baggrunden","large-print":"Forstørret tekst","page-breaks":{"compact":"Indeholder sideskift","descriptive":"Indeholder sideskift fra den trykte version af bogen"},"ruby-annotations":"Nogle \\"ruby\\" annotationer (til asiatiske sprog)","sign-language":"Tegnsprog","tactile-graphics":{"compact":"Indeholder taktil grafik","descriptive":"Indeholder taktil grafik for at muliggøre adgang til visuel information for blinde"},"tactile-objects":"Taktile 3D objekter","text-to-speech-hinting":"Udtaleforbedringer til syntetisk tale","title":"Yderligere information om tilgængelighed","ultra-high-contrast-between-text-and-background":"Ultra høj kontrast imellem tekst og baggrund","visible-page-numbering":"Synlige sidenumre","without-background-sounds":"Uden baggrundslyd"},"conformance":{"a":{"compact":"Denne bog overholder minimum-tilgængelighedskravene","descriptive":"Denne bog en overensstemmelseserklæring om, at den opfylder EPUB Tilgængelighedskrav og WCAG 2 standarden på niveau A"},"aa":{"compact":"Denne bog lever op til de accepterede tilgængelighedskrav","descriptive":"Denne bog en overensstemmelseserklæring om, at den opfylder EPUB Tilgængelighedskrav og WCAG 2 standarden på niveau AA"},"aaa":{"compact":"Denne bog mere end opfylder de accepterede tilgængelighedskrav","descriptive":"Denne bog en overensstemmelseserklæring om, at den opfylder EPUB Tilgængelighedskrav og WCAG 2 standarden på niveau AAA"},"certifier":"Denne bog blev certificeret af ","certifier-credentials":"Certificeringsorganets legitimationsoplysninger er ","details":{"certification-info":"Bogen blev certificeret den ","certifier-report":"Se certificeringsorganets rapport for mere information","claim":"Denne bog hævder at opfylde","epub-accessibility-1-0":"EPUB Tilgængelighed 1.0","epub-accessibility-1-1":"EPUB Tilgængelighed 1.1","level-a":"Niveau A","level-aa":"Niveau AA","level-aaa":"Niveau AAA","wcag-2-0":{"compact":"WCAG 2.0","descriptive":"Retningslinjer for tilgængeligt webindhold (WCAG) 2.0"},"wcag-2-1":{"compact":"WCAG 2.1","descriptive":"Retningslinjer for tilgængeligt webindhold (WCAG) 2.1"},"wcag-2-2":{"compact":"WCAG 2.2","descriptive":"Retningslinjer for tilgængeligt webindhold (WCAG) 2.2"}},"details-title":"Detaljeret overholdelses-information","no":"Ingen information tilgængelig","title":"Overholdelse","unknown-standard":"Overholdelse af de accepterede tilgængelighedskrav kan ikke vurderes for denne bog"},"hazards":{"flashing":{"compact":"Blinkende indhold","descriptive":"Bogen indeholder blinkende indhold der kan forårsage epileptiske anfald"},"flashing-none":{"compact":"Ingen blinkende indhold","descriptive":"Bogen indeholder ikke noget blinkende indhold, der kunne forårsage epileptiske anfald"},"flashing-unknown":{"compact":"Ingen information om bogen har blinkende indhold","descriptive":"Det kunne ikke afgøres om bogen indeholder blinkende indhold der kan lede til epileptiske anfald"},"motion":{"compact":"Simuleret bevægelse","descriptive":"Bogen indeholder simuleret bevægelse, der kan forårsage en følelse af køresyge"},"motion-none":{"compact":"Indeholder ikke simuleret bevægelse","descriptive":"Denne bog indeholder ikke noget indhold med simuleret bevægelse, der kunne lede til en følelse af køresyge"},"motion-unknown":{"compact":"Ingen information om simuleret bevægelse","descriptive":"Det kunne ikke vurderes om bogen indeholder simuleret bevægelse, der kan lede til en følelse af køresyge"},"no-metadata":"Ingen information tilgængelig","none":{"compact":"Ingen farer","descriptive":"Bogen indeholder ikke noget indhold der kategoriseres som farligt"},"sound":{"compact":"Lyde","descriptive":"Bogen indeholder lyde der kan være ubehagelige hvis man er sensitiv overfor lyde"},"sound-none":{"compact":"Ingen ubehagelige lyde","descriptive":"Bogen indeholder ikke lyde der kunne opleves som ubehagelige hvis man er sensitiv overfor lyde"},"sound-unknown":{"compact":"Ingen information om ubehagelige lyde","descriptive":"Det kunne ikke afgøres om bogen indeholder ubehagelige lyde"},"title":"Farer","unknown":"Ingen information om farligt indhold"},"legal-considerations":{"exempt":{"compact":"Gør krav på undtagelser fra tilgængelighedskrav","descriptive":"Denne bog gør krav på en tilgængelighedsundtagelse i en eller flere jurisdiktioner"},"no-metadata":"Ingen information tilgængelig","title":"Juridiske overvejelser"},"navigation":{"index":{"compact":"Indholdsfortegnelse","descriptive":"Indholdsfortegnelse med links til referencer"},"no-metadata":"Ingen information tilgængelig","page-navigation":{"compact":"Gå til side","descriptive":"Sideliste for at gå til sider fra den trykte kildeversion"},"structural":{"compact":"Overskrifter","descriptive":"Elementer så som overskrifter og tabeller til struktureret navigation"},"title":"Navigation","toc":{"compact":"Indholdsfortegnelse","descriptive":"Indholdsfortegnelse med links til alle kapitler"}},"rich-content":{"accessible-chemistry-as-latex":{"compact":"Kemiske formularer i LaTeX","descriptive":"Kemiske formularer i tilgængeligt format (LaTeX)"},"accessible-chemistry-as-mathml":{"compact":"Kemiske formularer i MathML notation","descriptive":"Kemiske formularer i tilgængeligt format (MathML)"},"accessible-math-as-latex":{"compact":"Matematik som LaTeX","descriptive":"Matematikformler i tilgængeligt format (LaTeX)"},"accessible-math-described":"Tekstbeskrivelser til matematiske formler","closed-captions":{"compact":"Videoer har undertekster","descriptive":"Videoer der optræder i bogen har undertekster"},"extended-descriptions":"Informationsrige billeder beskrives med udvidede beskrivelser","math-as-mathml":{"compact":"Matematik som MathML","descriptive":"Matematiske formler i tilgængeligt format (MathML)"},"open-captions":{"compact":"Videoer har indlejrede undertekster","descriptive":"Videoer der optræder i bogen har indlejrede undertekster"},"title":"Komplekst indhold","transcript":"Indeholder transskription(er)","unknown":"Ingen information tilgængelig"},"ways-of-reading":{"nonvisual-reading":{"alt-text":{"compact":"Har alternativ tekst","descriptive":"Har billedbeskrivelser"},"no-metadata":"Ingen information omkring ikke-visuel læsning","none":{"compact":"Ikke læsbar med oplæsning eller dynamisk punktskrift","descriptive":"Dette indhold er ikke læsbart med oplæsning eller dynamisk punktskrift"},"not-fully":{"compact":"Ikke fuldt læsbar med oplæsning eller dynamisk punktskrift","descriptive":"Alt indholdet er ikke fuldt læsbart med oplæsning eller dynamisk punktskrift"},"readable":{"compact":"Læsbar med oplæsning eller dynamisk punktskrift","descriptive":"Alt indholdet er læsbart med oplæsning eller dynamisk punktskrift"}},"prerecorded-audio":{"complementary":{"compact":"Indlæste lydklip","descriptive":"Indlæste lydklip er indlejret i indholdet"},"no-metadata":"Ingen information om indlæst lyd","only":{"compact":"Kun indlæst lyd","descriptive":"Lydbog uden tekst alternativer"},"synchronized":{"compact":"Indlæst lyd med synkroniseret tekst","descriptive":"Alt indholdet er tilgængeligt med indlæst lyd og synkroniseret tekst"}},"title":"Læseformer","visual-adjustments":{"modifiable":{"compact":"Udseende kan ændres","descriptive":"Udseende af tekst og sidelayout kan ændres, så vidt muligt i læsesystemet (skrifttype, skriftstørrelse, afstand mellem afsnit, sætninger, ord og bogstaver, samt farven på tekst og baggrund)"},"unknown":"Ingen information om mulighed for ændring af udseende","unmodifiable":{"compact":"Udseende kan ikke ændres","descriptive":"Tekst og sidelayout kan ikke ændres, da læseoplevelsen afspejler den trykte version af materialet. Læsesystemet kan dog stadig give mulighed for zoom"}}}}},"altIdentifier_one":"alternativ identifikator","altIdentifier_other":"alternative identifikatorer","artist_one":"kunstner","artist_other":"kunstnere","author_one":"forfatter","author_other":"forfattere","collection_one":"redaktionel samling","collection_other":"redaktionelle samlinger","colorist_one":"farvelægger","colorist_other":"farvelæggere","contributor_one":"bidragsyder","contributor_other":"bidragsydere","description":"beskrivelse","duration":"varighed","editor_one":"redaktør","editor_other":"redaktører","identifier_one":"identifikator","identifier_other":"identifikatorer","illustrator_one":"illustrator","illustrator_other":"illustratorer","imprint_one":"forlagsaftryk","imprint_other":"forlagsaftryk","inker_one":"tegner","inker_other":"tegnere","language_one":"sprog","language_other":"sprog","letterer_one":"taleboble-forfatter","letterer_other":"taleboble-forfattere","modified":"rettet dato","narrator_one":"indlæser","narrator_other":"indlæsere","numberOfPages":"printbare sider","penciler_one":"tegneseriekunstner","penciler_other":"tegneseriekunstnere","published":"udgivelsesdato","publisher_one":"udgiver","publisher_other":"udgivere","series_one":"serie","series_other":"serier","subject_one":"emne","subject_other":"emner","subtitle":"undertitel","title":"titel","translator_one":"oversætter","translator_other":"oversættere"}}`),he={publication:me}})),_e=r({default:()=>ye,publication:()=>ve}),ve,ye,be=n((()=>{ve=JSON.parse(`{"format":{"audiobook":"Ακουστικό βιβλίο","audiobookJSON":"Έκδοση Ακουστικού βιβλίου","cbz":"Αρχείο βιβλίων κόμικς","divina":"Divina έκδοση","divinaJSON":"Διακήρυξη έκδοσης Divina","epub":"EPUB","lcpa":"LCP Προστατευμένο Ακουστικό βιβλίο","lcpdf":"LCP Προστατευμένο PDF","lcpl":"LCP Έγγραφο άδειας","pdf":"Έκδοση PDF","rwp":"Readium Web έκδοσης","rwpm":"Διακήρυξη Readium Web έκδοσης","zab":"Αρχείο Ακουστικών βιβλίων","zip":"Αρχείο ZIP"},"kind":{"audiobook_one":"ακουστικό βιβλίο","audiobook_other":"ακουστικά βιβλία","book_one":"βιβλίο","book_other":"βιβλία","comic_one":"κόμικ","comic_other":"κόμικς","document_one":"έγγραφο","document_other":"έγγραφα"},"metadata":{"accessibility":{"display-guide":{"accessibility-summary":{"no-metadata":"Καμιά διαθέσιμη πληροφορία","publisher-contact":"Για περισσότερες πληροφορίες σχετικά με αυτό το προϊόν, παρακαλούμε επικοινώνησε με τον εκδότη: ","title":"Σύνοψη προσβασιμότητας"},"additional-accessibility-information":{"aria":{"compact":"Περιλαμβάνονται ARIA roles","descriptive":"Το περιεχόμενο έχει εμπλουτιστεί με ARIA roles για τη βελτιστοποίηση της οργάνωσης και τη διευκόλυνση της πλοήγησης"},"audio-descriptions":"Περιγραφές ήχου","braille":"Braille","color-not-sole-means-of-conveying-information":"Το χρώμα δεν είναι το μόνο μέσο για τη διαβίβαση της πληροφορίας","dyslexia-readability":"Αναγνωσιμότητα προσαρμοσμένη σε άτομα με δυσλεξία","full-ruby-annotations":"Πλήρη σχόλια ruby","high-contrast-between-foreground-and-background-audio":"Υψηλή αντίθεση μεταξύ ήχου μπροστά και πίσω","high-contrast-between-text-and-background":"Υψηλή αντίθεση μεταξύ κείμενο πρώτου πλάνου και φόντου","large-print":"Μεγάλα στοιχεία","page-breaks":{"compact":"Περιλαμβάνονται αλλαγές σελίδας","descriptive":"Περιλαμβάνονται αλλαγές σελίδας από την πρωτότυπη έντυπη έκδοση"},"ruby-annotations":"Μερικά Ruby σχόλια","sign-language":"Νοηματική γλώσσα","tactile-graphics":{"compact":"Περιλαμβάνονται απτικά γραφικά","descriptive":"Έχουν ενσωματωθεί ανάγλυφα γραφικά για τη διευκόλυνση της πρόσβασης τυφλών ατόμων σε οπτικά στοιχεία"},"tactile-objects":"Απτικά 3D αντικείμενα","text-to-speech-hinting":"Παρέχεται υπόδειξη για βελτίωση Εκφώνησης κειμένου","title":"Πρόσθετες πληροφορίες προσβασιμότητας","ultra-high-contrast-between-text-and-background":"Εξαιρετικά υψηλή αντίθεση μεταξύ κειμένου και φόντου","visible-page-numbering":"Ορατή αρίθμηση σελίδων","without-background-sounds":"Χωρίς ήχους στο παρασκήνιο"},"conformance":{"a":{"compact":"Αυτή η δημοσίευση καλύπτει τις ελάχιστες απαιτήσεις προσβασιμότητας","descriptive":"Η δημοσίευση περιλαμβάνει δήλωση συμμόρφωσης που πιστοποιεί την πλήρωση των προτύπων EPUB Accessibility και WCAG 2 Level A"},"aa":{"compact":"Η δημοσίευση αυτή καλύπτει τα καθιερωμένα πρότυπα προσβασιμότητας","descriptive":"Η δημοσίευση περιλαμβάνει δήλωση συμμόρφωσης που πιστοποιεί την πλήρωση των προτύπων EPUB Accessibility και WCAG 2 Level AA"},"aaa":{"compact":"Αυτή η δημοσίευση υπερβαίνει τα αποδεκτά πρότυπα προσβασιμότητας","descriptive":"Η δημοσίευση περιλαμβάνει δήλωση συμμόρφωσης που πιστοποιεί την πλήρωση των προτύπων EPUB Accessibility και WCAG 2 Level AAA"},"certifier":"Η δημοσίευση πιστοποιήθηκε από ","certifier-credentials":"Διαπιστευτήρια φορέα πιστοποίησης είναι ","details":{"certification-info":"Η δημοσίευση πιστοποιήθηκε στις ","certifier-report":"Περισσότερες πληροφορίες στην έκθεση του φορέα πιστοποίησης","claim":"Η παρούσα δημοσίευση υποστηρίζει ότι πληροί","epub-accessibility-1-0":"Έκδοση EPUB Accessibility 1.0","epub-accessibility-1-1":"Έκδοση EPUB Accessibility 1.1","level-a":"Επίπεδο Α","level-aa":"Επίπεδο ΑΑ","level-aaa":"Επίπεδο ΑΑΑ","wcag-2-0":{"compact":"Έκδοση WCAG 2.0","descriptive":"Οδηγίες για την Προσβασιμότητα του Περιεχομένου του Ιστού (WCAG) 2.0"},"wcag-2-1":{"compact":"Έκδοση WCAG 2.1","descriptive":"Οδηγίες για την Προσβασιμότητα του Περιεχομένου του Ιστού (WCAG) 2.1"},"wcag-2-2":{"compact":"Έκδοση WCAG 2.2","descriptive":"Οδηγίες για την Προσβασιμότητα του Περιεχομένου του Ιστού (WCAG) 2.2"}},"details-title":"Πληροφορίες σχετικά με τη συμμόρφωση","no":"Δεν υπάρχουν διαθέσιμες πληροφορίες","title":"Συμμόρφωση","unknown-standard":"Η συμμόρφωση με τα αποδεκτά πρότυπα προσβασιμότητας της παρούσας έκδοσης δεν μπορεί να προσδιοριστεί"},"hazards":{"flashing":{"compact":"Αναβοσβήνον περιεχόμενο","descriptive":"Η έκδοση περιέχει αναβοσβήνον περιεχόμενο και μπορεί να προκαλέσει φωτοευαίσθητες κρίσεις"},"flashing-none":{"compact":"Χωρίς κίνδυνο από αναβοσβήνον περιεχόμενο","descriptive":"Η έκδοση δεν περιέχει αναβοσβήνον περιεχόμενο, το οποίο μπορεί να προκαλέσει φωτοευαίσθητες κρίσεις"},"flashing-unknown":{"compact":"Δεν είναι γνωστό αν υπάρχουν κίνδυνοι λόγω αναβοσβήνοντος περιεχομένου","descriptive":"Δεν ήταν δυνατό να διαπιστωθεί η παρουσία αναβοσβήνοντος περιεχομένου που μπορεί να προκαλέσει φωτοευαίσθητες κρίσεις"},"motion":{"compact":"Προσομοίωση κίνησης","descriptive":"Η δημοσίευση περιέχει προσομοιώσεις κίνησης που μπορεί να προκαλέσουν ναυτία"},"motion-none":{"compact":"Δεν υπάρχουν κίνδυνοι από την προσομοίωση κίνησης","descriptive":"Η δημοσίευση δεν περιέχει προσομοιώσεις κίνησης που μπορεί να προκαλέσουν ναυτία"},"motion-unknown":{"compact":"Δεν είναι γνωστό αν υπάρχουν κίνδυνοι λόγω προσομοίωσης κίνησης","descriptive":"Δεν ήταν δυνατό να διαπιστωθεί η ύπαρξη προσομοιώσεων κίνησης που μπορούν να προκαλέσουν ναυτία"},"no-metadata":"Δεν υπάρχουν διαθέσιμες πληροφορίες","none":{"compact":"Δεν υπάρχουν κίνδυνοι","descriptive":"Η δημοσίευση δεν περιέχει κινδύνους"},"sound":{"compact":"Ήχοι","descriptive":"Η δημοσίευση περιέχει ήχους που ενδέχεται να προκαλέσουν αισθητηριακά προβλήματα"},"sound-none":{"compact":"Κανένας κίνδυνος που σχετίζεται με τον ήχο","descriptive":"Η δημοσίευση δεν περιέχει ήχους που ενδέχεται να προκαλέσουν αισθητηριακά προβλήματα"},"sound-unknown":{"compact":"Δεν είναι γνωστό αν υπάρχουν ηχητικοί κίνδυνοι","descriptive":"Δεν ήταν δυνατό να διαπιστωθεί η παρουσία ήχων που ενδέχεται να προκαλέσουν προβλήματα αισθητηριακής ευαισθησίας"},"title":"Κίνδυνοι","unknown":"Η ύπαρξη κινδύνων είναι άγνωστη"},"legal-considerations":{"exempt":{"compact":"Απαιτεί εξαίρεση από τους κανόνες προσβασιμότητας σε ορισμένες τοπικές δικαιοδοσίες","descriptive":"Αυτή η δημοσίευση απαιτεί εξαίρεση από τους κανόνες προσβασιμότητας σε ορισμένες τοπικές δικαιοδοσίες"},"no-metadata":"Δεν διατίθενται πληροφορίες","title":"Νομικά ζητήματα"},"navigation":{"index":{"compact":"Ευρετήριο","descriptive":"Ευρετήριο με συνδέσμους προς τις αναφερόμενες καταχωρήσεις"},"no-metadata":"Δεν διατίθενται πληροφορίες","page-navigation":{"compact":"Μετάβαση σε σελίδα","descriptive":"Λίστα πλοήγησης σελιδαρίθμησης με βάση την έντυπη έκδοση περιεχομένου"},"structural":{"compact":"Επικεφαλίδες","descriptive":"Στοιχεία όπως επικεφαλίδες, πίνακες κ.λπ. για δομημένη πλοήγηση"},"title":"Πλοήγηση","toc":{"compact":"Πίνακας περιεχομένων","descriptive":"Δυναμικός πίνακας περιεχομένων για όλα τα κεφάλαια"}},"rich-content":{"accessible-chemistry-as-latex":{"compact":"Χημικοί τύποι σε LaTeX","descriptive":"Χημικοί τύποι σε προσβάσιμο μορφότυπο (LaTeX)"},"accessible-chemistry-as-mathml":{"compact":"Χημικοί τύποι σε MathML","descriptive":"Χημικοί τύποι σε προσβάσιμο μορφότυπο (MathML)"},"accessible-math-as-latex":{"compact":"Μαθηματικά σε LaTeX","descriptive":"Μαθηματικοί τύποι σε προσβάσιμο μορφότυπο (LaTeX)"},"accessible-math-described":"Παρέχονται κειμενικές περιγραφές μαθηματικών","closed-captions":{"compact":"Bίντεο με ενσωματωμένους υπότιτλους","descriptive":"Τα βίντεο που περιέχονται σε δημοσιεύσεις διαθέτουν ενσωματωμένους υπότιτλους"},"extended-descriptions":"Οι σύνθετες εικόνες περιγράφονται με εκτεταμένες περιγραφές","math-as-mathml":{"compact":"Μαθηματικά σε MathML","descriptive":"Μαθηματικοί τύποι σε προσβάσιμο μορφότυπο (MathML)"},"open-captions":{"compact":"Τα βίντεο έχουν σταθερό υποτιτλισμό (open captions)","descriptive":"Τα συμπεριλαμβανόμενα βίντεο στις δημοσιεύσεις έχουν σταθερό υποτιτλισμό (open captions)"},"title":"Εμπλουτισμένο περιεχόμενο","transcript":"Διαθέσιμη απομαγνητοφώνηση","unknown":"Δεν διατίθενται πληροφορίες"},"ways-of-reading":{"nonvisual-reading":{"alt-text":{"compact":"Έχει εναλλακτικό κείμενο","descriptive":"Έχει εναλλακτικό κείμενο περιγραφής για εικόνες"},"no-metadata":"Δεν υπάρχουν διαθέσιμες πληροφορίες σχετικά με τη μη οπτική ανάγνωση","none":{"compact":"Δεν είναι δυνατή η ανάγνωση με εκφώνηση ή δυναμικό Braille","descriptive":"Το περιεχόμενο δεν είναι αναγνώσιμο μέσω εκφώνησης ή δυναμικής γραφής Braille"},"not-fully":{"compact":"Δεν είναι πλήρως αναγνώσιμο με εκφώνηση ή με δυναμική γραφή Braille","descriptive":"Δεν θα είναι αναγνώσιμο όλο το περιεχόμενο μέσω εκφώνησης ή δυναμικής γραφής Braille"},"readable":{"compact":"Είναι αναγνώσιμο με εκφώνηση ή με δυναμική γραφής Braille","descriptive":"Όλο το περιεχόμενο μπορεί να αναγνωστεί μέσω εκφώνησης ή δυναμικής γραφής Braille"}},"prerecorded-audio":{"complementary":{"compact":"Προ-ηχογραφημένα αρχεία ήχου","descriptive":"Προ-ηχογραφημένα αρχεία ήχου είναι ενσωματωμένα στο περιεχόμενο"},"no-metadata":"Δεν υπάρχουν διαθέσιμες πληροφορίες σχετικά με τον προ-ηχογραφημένο ήχο","only":{"compact":"Μόνο προηχογραφημένος ήχος","descriptive":"Ακουστικό βιβλίο χωρίς εναλλακτικό κείμενο"},"synchronized":{"compact":"Προηχογραφημένος ήχος συγχρονισμένος με το κείμενο","descriptive":"Όλο το περιεχόμενο διατίθεται ως προηχογραφημένος ήχος συγχρονισμένος με το κείμενο"}},"title":"Τρόποι διαβάσματος","visual-adjustments":{"modifiable":{"compact":"Η εμφάνιση μπορεί να τροποποιείται","descriptive":"Η εμφάνιση του κειμένου και η διάταξη της σελίδας μπορούν να τροποποιηθούν ανάλογα με τις δυνατότητες του συστήματος ανάγνωσης (γραμματοσειρά και μέγεθος γραμματοσειράς, διαστήματα μεταξύ παραγράφων, προτάσεων, λέξεων και γραμμάτων, καθώς και χρώμα φόντου και κειμένου)"},"unknown":"Δεν διατίθενται πληροφορίες σχετικά με τη δυνατότητα τροποποίησης της εμφάνισης","unmodifiable":{"compact":"Η εμφάνιση δεν μπορεί να τροποποιηθεί","descriptive":"Το κείμενο και η διάταξη της σελίδας δεν μπορούν να τροποποιηθούν, καθώς η εμπειρία ανάγνωσης προσεγγίζει εκείνη της έντυπης έκδοσης, αλλά τα συστήματα ανάγνωσης εξακολουθούν να προσφέρουν επιλογές μεγέθυνσης"}}}}},"altIdentifier_one":"εναλλακτικό αναγνωριστικό","altIdentifier_other":"εναλλακτικοί αναγνωριστικοί","artist_one":"καλλιτέχνης","artist_other":"καλλιτέχνες","author_one":"Συγγραφέας","author_other":"Συγγραφείς","collection_one":"εκδοτική συλλογή","collection_other":"εκδοτικές συλλογές","colorist_one":"κόλοριστ","colorist_other":"κόλοριστς","contributor_one":"συντελεστής","contributor_other":"συντελεστές","description":"περιγραφή","duration":"διάρκεια","editor_one":"επιμελητής","editor_other":"επιμελητές","identifier_one":"αναγνωριστικό","identifier_other":"αναγνωριστικά","illustrator_one":"εικονογράφος","illustrator_other":"εικονογράφοι","imprint_one":"εκδοτικό σήμα","imprint_other":"εκδοτικά σήματα","inker_one":"ίνκερ","inker_other":"ίνκερς","language_one":"γλώσσα","language_other":"γλώσσες","letterer_one":"λεττερίστας / λεττερίστρια","letterer_other":"λεττερίστες / λεττερίστριες","modified":"ημερομηνία τροποποίησης","narrator_one":"αφηγητής / αφηγήτρια","narrator_other":"αφηγητές / αφηγήτριες","numberOfPages":"μήκος εκτύπωσης","penciler_one":"Σχεδιαστής / Σχεδιάστρια","penciler_other":"Σχεδιαστές / Σχεδιάστριες","published":"ημερομηνία έκδοσης","publisher_one":"εκδότης","publisher_other":"εκδότες","series_one":"σειρά","series_other":"σειρές","subject_one":"θέμα","subject_other":"θέματα","subtitle":"υπότιτλος","title":"τίτλος","translator_one":"μεταφραστής / μεταφράστρια","translator_other":"μεταφραστές / μεταφράστριες"}}`),ye={publication:ve}})),xe=r({default:()=>Ce,publication:()=>Se}),Se,Ce,we=n((()=>{Se=JSON.parse(`{"format":{"audiobook":"Audiolibro","audiobookJSON":"Manifiesto de Audiolibro","cbz":"Tira cómica","divina":"Publicación Divina","divinaJSON":"Manifiesto de Publicación Divina","epub":"EPUB","lcpa":"Audiolibro Protegido con LCP","lcpdf":"PDF Protegido con LCP","lcpl":"Documento de Licencia LCP","pdf":"PDF","rwp":"Publicación Web Readium","rwpm":"Manifiesto de Publicación Web Readium","zab":"Archivo de Audiolibro","zip":"Archivo ZIP"},"kind":{"audiobook_many":"audio‐libros","audiobook_one":"audio‐libro","audiobook_other":"audio‐libros","book_many":"libros","book_one":"libro","book_other":"libros","comic_many":"cómics","comic_one":"cómic","comic_other":"cómics","document_many":"documentos","document_one":"documento","document_other":"documentos"},"metadata":{"accessibility":{"display-guide":{"accessibility-summary":{"no-metadata":"No hay información disponible","publisher-contact":"Para más información sobre la accesibilidad de este producto, póngase en contacto con la editorial: ","title":"Información adicional sobre accesibilidad proporcionada por la editorial"},"additional-accessibility-information":{"aria":{"compact":"Información enriquecida para tecnologías de asistencia","descriptive":"El contenido se ha enriquecido con roles ARIA para optimizar la organización y facilitar la navegación"},"audio-descriptions":"Audiodescripciones","braille":"Braille","color-not-sole-means-of-conveying-information":"El color no es el único medio para transmitir información","dyslexia-readability":"Legibilidad para dislexia","full-ruby-annotations":"Anotaciones ruby completas","high-contrast-between-foreground-and-background-audio":"Alto contraste entre audio principal y de fondo","high-contrast-between-text-and-background":"Alto contraste entre texto principal y fondo","large-print":"Impresión grande","page-breaks":{"compact":"Se incluyen saltos de página","descriptive":"Se incluyen saltos de página procedentes de la fuente original"},"ruby-annotations":"Algunas anotaciones ruby","sign-language":"Lengua de signos","tactile-graphics":{"compact":"Se incluyen gráficos táctiles","descriptive":"Se han incorporado gráficos táctiles para facilitar a personas ciegas el acceso a elementos visuales"},"tactile-objects":"Objetos 3D táctiles","text-to-speech-hinting":"Se ofrecen indicaciones de texto a voz","title":"Información adicional sobre accesibilidad","ultra-high-contrast-between-text-and-background":"Contraste ultra alto entre texto principal y fondo","visible-page-numbering":"Numeración de página visible","without-background-sounds":"Sin sonidos de fondo"},"conformance":{"a":{"compact":"Esta publicación cumple con estándares mínimos de accesibilidad","descriptive":"La publicación contiene una declaración de conformidad de cumplimiento del estándar de accesibilidad EPUB y WCAG 2 nivel A"},"aa":{"compact":"Esta publicación cumple con estándares aceptados de accesibilidad","descriptive":"La publicación contiene una declaración de conformidad de cumplimiento del estándar de accesibilidad EPUB y WCAG 2 nivel AA"},"aaa":{"compact":"Esta publicación sobrepasa los estándares aceptados de accesibilidad","descriptive":"La publicación contiene una declaración de conformidad de cumplimiento del estándar de accesibilidad EPUB y WCAG 2 nivel AAA"},"certifier":"La publicación fue evaluada por ","certifier-credentials":"La credencial del evaluador es ","details":{"certification-info":"La publicación fue evaluada en ","certifier-report":"Para más información, consulte el informe del evaluador","claim":"Esta publicación declara que cumple","epub-accessibility-1-0":"Accesibilidad EPUB 1.0","epub-accessibility-1-1":"Accesibilidad EPUB 1.1","level-a":"Nivel A","level-aa":"Nivel AA","level-aaa":"Nivel AAA","wcag-2-0":{"compact":"WCAG 2.0","descriptive":"Reglas para la accesibilidad del contenido web (WCAG) 2.0"},"wcag-2-1":{"compact":"WCAG 2.1","descriptive":"Reglas para la accesibilidad del contenido web (WCAG) 2.1"},"wcag-2-2":{"compact":"WCAG 2.2","descriptive":"Reglas para la accesibilidad del contenido web (WCAG) 2.2"}},"details-title":"Información de conformidad detallada","no":"No hay información disponible","title":"Conformidad","unknown-standard":"No es posible determinar la conformidad con estándares para la accesibilidad de esta publicación"},"hazards":{"flashing":{"compact":"Contenido con destellos","descriptive":"La publicación incluye contenido con destellos que puede causar convulsiones fotosensibles"},"flashing-none":{"compact":"No hay contenido con destellos","descriptive":"La publicación no incluye contenido con destellos"},"flashing-unknown":{"compact":"Se desconoce la presencia de contenido con destellos","descriptive":"Se desconoce la presencia de contenido con destellos que pueda causar convulsiones fotosensibles"},"motion":{"compact":"Simulación de movimiento","descriptive":"La publicación contiene simulaciones de movimiento que pueden causar mareo"},"motion-none":{"compact":"No hay simulación de movimiento","descriptive":"La publicación no incluye simulación de movimiento"},"motion-unknown":{"compact":"Se desconoce la presencia de simulación de movimiento","descriptive":"Se desconoce la presencia de simulaciones de movimiento que pueden causar mareo"},"no-metadata":"No hay información disponible","none":{"compact":"No hay incidencias","descriptive":"La publicación no incluye contenido con incidencias"},"sound":{"compact":"Sonidos","descriptive":"La publicación contiene sonidos que pueden ser incómodos"},"sound-none":{"compact":"No hay sonidos","descriptive":"La publicación no contiene sonidos"},"sound-unknown":{"compact":"No hay información sobre la presencia de sonidos","descriptive":"Se desconoce la presencia de sonidos que puedan causar problemas de sensibilidad"},"title":"Incidencias","unknown":"Se desconoce si existen incidencias"},"legal-considerations":{"exempt":{"compact":"Reclama una exención de accesibilidad en algunas jurisdicciones","descriptive":"Esta publicación reclama una exención de accesibilidad en algunas jurisdicciones"},"no-metadata":"No hay información disponible","title":"Consideraciones legales"},"navigation":{"index":{"compact":"Índice","descriptive":"Índice con enlaces a entradas referenciadas"},"no-metadata":"No hay información disponible","page-navigation":{"compact":"Ir a página","descriptive":"Lista de páginas para ir a páginas tomando como fuente la versión impresa"},"structural":{"compact":"Encabezados","descriptive":"Elementos como encabezados, tablas, etc. para una navegación estructurada"},"title":"Navegación","toc":{"compact":"Tabla de contenido","descriptive":"Tabla de contenido con enlaces a todos los capítulos del texto"}},"rich-content":{"accessible-chemistry-as-latex":{"compact":"Fórmulas químicas en LaTeX","descriptive":"Fórmulas químicas en formato accesible (LaTeX)"},"accessible-chemistry-as-mathml":{"compact":"Fórmulas químicas en MathML","descriptive":"Fórmulas químicas en formato accesible (MathML)"},"accessible-math-as-latex":{"compact":"Matemáticas como LaTeX","descriptive":"Matemáticas en formato accesible (LaTeX)"},"accessible-math-described":"Se proporcionan descripciones de texto para matemáticas","closed-captions":{"compact":"Los vídeos tienen subtítulos opcionales","descriptive":"Los vídeos incluidos en las publicaciones tienen subtítulos opcionales"},"extended-descriptions":"Las imágenes con información abundante disponen de descripciones extensas","math-as-mathml":{"compact":"Matemáticas como MathML","descriptive":"Fórmulas matemáticas en formato accesible (MathML)"},"open-captions":{"compact":"Los vídeos tienen subtítulos incrustados","descriptive":"Los vídeos incluidos en las publicaciones tienen subtítulos incrustados"},"title":"Contenido enriquecido","transcript":"Se proporcionan transcripciones","unknown":"No hay información disponible"},"ways-of-reading":{"nonvisual-reading":{"alt-text":{"compact":"Tiene texto alternativo","descriptive":"Tiene descripciones para imágenes mediante texto alternativo"},"no-metadata":"No hay información disponible sobre lectura con síntesis de voz o en braille","none":{"compact":"No se puede leer con síntesis de voz ni en braille","descriptive":"El contenido no se puede leer con síntesis de voz ni en braille"},"not-fully":{"compact":"No se puede leer completamente con síntesis de voz ni en braille","descriptive":"No todo el contenido podrá leerse con síntesis de voz ni en braille"},"readable":{"compact":"Se puede leer con síntesis de voz y en braille","descriptive":"Todo el contenido se puede leer con síntesis de voz y en braille"}},"prerecorded-audio":{"complementary":{"compact":"Clips de audio pregrabados","descriptive":"En el contenido se integran clips de audio pregrabados"},"no-metadata":"No hay información disponible sobre audio pregrabado","only":{"compact":"Solo audio pregrabado","descriptive":"Audiolibro sin texto alternativo"},"synchronized":{"compact":"Audio pregrabado sincronizado con texto","descriptive":"Todo el contenido está disponible como audio pregrabado sincronizado con texto"}},"title":"Legibilidad","visual-adjustments":{"modifiable":{"compact":"Es posible modificar el aspecto visual","descriptive":"El aspecto visual del texto y el diseño de página se pueden modificar en función de las posibilidades del sistema de lectura (familia y tamaño de fuente, espacios entre párrafos, frases, palabras y letras, así como el color de fondo y texto)"},"unknown":"No hay información disponible sobre la posibilidad de modificar el aspecto visual","unmodifiable":{"compact":"No es posible modificar el aspecto visual","descriptive":"El texto y el diseño de página no se pueden modificar porque la experiencia de lectura es similar a la de la versión impresa, pero los sistemas de lectura pueden seguir ofreciendo opciones de ampliación"}}}}},"altIdentifier_many":"identificador alternativo/s","altIdentifier_one":"identificador alternativo","altIdentifier_other":"identificadores alternativos","artist_many":"artista(s)","artist_one":"artista","artist_other":"artistas","author_many":"autor/es","author_one":"autor","author_other":"autores","collection_many":"colecciones editoriales","collection_one":"colección editorial","collection_other":"colecciones editoriales","colorist_many":"colorista(s)","colorist_one":"colorista","colorist_other":"coloristas","contributor_many":"colaborador(es)","contributor_one":"colaborador","contributor_other":"colaboradores","description":"descripción","duration":"duración","editor_many":"editor(es)","editor_one":"editor","editor_other":"editores","identifier_many":"identificador(es)","identifier_one":"identificador","identifier_other":"identificadores","illustrator_many":"ilustrador(es)","illustrator_one":"ilustrador","illustrator_other":"ilustradores","imprint_many":"marca(s) editorial(es)","imprint_one":"marca editorial","imprint_other":"marcas editoriales","inker_many":"entintador(es)","inker_one":"entintador","inker_other":"entintadores","language_many":"idioma(s)","language_one":"idioma","language_other":"idiomas","letterer_many":"rotulista(s)","letterer_one":"rotulista","letterer_other":"rotulistas","modified":"fecha de modificación","narrator_many":"narrador(es)","narrator_one":"narrador","narrator_other":"narradores","numberOfPages":"número de páginas","penciler_many":"dibujante(s)","penciler_one":"dibujante","penciler_other":"dibujantes","published":"fecha de publicación","publisher_many":"editorial(es)","publisher_one":"editorial","publisher_other":"editoriales","series_many":"serie(s)","series_one":"serie","series_other":"series","subject_many":"tema(s)","subject_one":"tema","subject_other":"temas","subtitle":"subtítulo","title":"título","translator_many":"traductor(es)","translator_one":"traductor","translator_other":"traductores"}}`),Ce={publication:Se}})),Te=r({default:()=>De,publication:()=>Ee}),Ee,De,Oe=n((()=>{Ee=JSON.parse(`{"format":{"audiobook":"Heliraamat","audiobookJSON":"Heliraamatu manifest","cbz":"Comic Booki arhiiv","divina":"Divina väljaanne","divinaJSON":"Divina väljaande manifest","epub":"EPUB","lcpa":"LCP-kaitsega heliraamat","lcpdf":"LCP-kaitsega PDF-fail","lcpl":"LCP-litsentsiga dokument","pdf":"PDF-fail","rwp":"Readiumi veebiväljaanne","rwpm":"Readiumi veebiväljaande manifest","zab":"Heliraamatu arhiiv","zip":"ZIP-arhiiv"},"kind":{"audiobook_one":"heliraamat","audiobook_other":"heliraamatud","book_one":"raamat","book_other":"raamatud","comic_one":"koomiks","comic_other":"koomiksid","document_one":"dokument","document_other":"dokumendid"},"metadata":{"accessibility":{"display-guide":{"accessibility-summary":{"no-metadata":"Teave pole saadaval","publisher-contact":"Selle toote saadavause osas palun küsi lisateavet kirjastusest: ","title":"Saadavuse kokkuvõte"},"additional-accessibility-information":{"aria":{"compact":"ARIA rollid on lisatud","descriptive":"Sisu on täiendatud ARIA-rollidega, et optimeerida selle ülesehitust ja hõlbustada väljaandes liikumist"},"audio-descriptions":"Helikirjeldus","braille":"Punktkiri (Braille'i kiri)","color-not-sole-means-of-conveying-information":"Värv pole ainus viis teabe edastamiseks","dyslexia-readability":"Kohandatud lugemisraskustega inimestele","full-ruby-annotations":"Täismahus märkused Ruby-vormingus (Aasia keeled)","high-contrast-between-foreground-and-background-audio":"Suur kontrast esiplaani ja taustahelide vahel","high-contrast-between-text-and-background":"Suur kontrast esiplaani teksti ja tausta vahel","large-print":"Suurte tähemärkidega kiri","page-breaks":{"compact":"Lehevahetused on olemas","descriptive":"Lehevahetused on pärit algsest trükivariandist"},"ruby-annotations":"Mõned märkused Ruby-vormingus (Aasia keeled)","sign-language":"Viipekeel","tactile-graphics":{"compact":"Puutegraafika on olemas","descriptive":"Pimedatele inimestele visuaalsete elementide kättesaadavuse hõlbustamiseks on lisatud reljeefgraafika (puutegraafika)"},"tactile-objects":"Puudutustundlikud kolmemõõtmelised objektid","text-to-speech-hinting":"Kõnesünteesi vihjed on lisatud","title":"Täiendav hõlbustusteave","ultra-high-contrast-between-text-and-background":"Teksti ja tausta vahel on äärmiselt suur kontrast","visible-page-numbering":"Nähtav lehtede nummerdus","without-background-sounds":"Ilma taustahelideta"},"conformance":{"a":{"compact":"Käesolev väljaanne vastab hõlbustuse ja ligipääsetavuse miinimumnõuetele","descriptive":"Väljaanne sisaldab vastavusdeklaratsiooni, mille kohaselt vastab see EPUB-i hõlbustusstandardile ja WCAG 2. taseme A-nõuetele"},"aa":{"compact":"Käesolev väljaanne vastab kehtivatele hõlbustuse ja ligipääsetavuse standarditele","descriptive":"Väljaanne sisaldab vastavusdeklaratsiooni, mille kohaselt vastab see EPUB-i hõlbustusstandardile ja WCAG 2. taseme AA-nõuetele"},"aaa":{"compact":"Käesolev väljaanne ületab kehtivaid hõlbustuse ja ligipääsetavuse standardeid","descriptive":"Väljaanne sisaldab vastavusdeklaratsiooni, mille kohaselt vastab see EPUB-i hõlbustusstandardile ja WCAG 2. taseme AAA-nõuetele"},"certifier":"Selle väljaande on sertifitseerinud ","certifier-credentials":"Sertifitseerija tunnus on ","details":{"certification-info":"Sertifitseerimise ajatempel on ","certifier-report":"Lisateavet leiad sertifitseerija aruandest","claim":"Käesolev väljaanne väidab, et olemas on vastavus standardiga","epub-accessibility-1-0":"EPUB-i hõlbustusstandardi versioon 1.0","epub-accessibility-1-1":"EPUB-i hõlbustusstandardi versioon 1.1","level-a":"A-tase","level-aa":"AA-tase","level-aaa":"AAA-tase","wcag-2-0":{"compact":"WCAG 2.0","descriptive":"Veebisisu hõlbustuse juhised (WCAG) 2.0"},"wcag-2-1":{"compact":"WCAG 2.1","descriptive":"Veebisisu hõlbustuse juhised (WCAG) 2.1"},"wcag-2-2":{"compact":"WCAG 2.2","descriptive":"Veebisisu hõlbustuse juhised (WCAG) 2.2"}},"details-title":"Üksikasjalik teave vastavuse kohta","no":"Teave pole saadaval","title":"Vastavus","unknown-standard":"Selle väljaande vastavust kehtivatele hõlbustuse ja ligipääsetavuse standarditele ei ole võimalik kindlaks teha"},"hazards":{"flashing":{"compact":"Vilkuv sisu","descriptive":"See väljaanne sisaldab vilkuvat sisu, mis võib põhjustada valgustundlikusest johtuvaid krampe"},"flashing-none":{"compact":"Vilkumisega seotud ohte pole","descriptive":"See väljaanne ei sisalda vilkuvat sisu, mis võib põhjustada valgustundlikusest johtuvaid krampe"},"flashing-unknown":{"compact":"Vilkumisega seotud ohud pole teada","descriptive":"Pole võimalik kindlaks teha, kas selles väljaandes leidub vilkuvat sisu, mis võib põhjustada valgustundlikusest johtuvaid krampe"},"motion":{"compact":"Simuleeritud liikumine","descriptive":"Väljaanne sisaldab liikumissimulatsioone, mis võivad põhjustada liikumistõbe"},"motion-none":{"compact":"Simuleeritud liikumisega seotud ohte pole","descriptive":"Väljaanne ei sisalda liikumissimulatsioone, mis võivad põhjustada liikumistõbe"},"motion-unknown":{"compact":"Simuleeritud liikumisega seotud ohud pole teada","descriptive":"Ei õnnestu tuvastada, kas väljaanne sisaldab liikumissimulatsioone, mis võivad põhjustada liikumistõbe"},"no-metadata":"Teave pole saadaval","none":{"compact":"Ohte pole","descriptive":"Selles väljaandes ei leidu ohte"},"sound":{"compact":"Helid","descriptive":"Väljaanne sisaldab helisid, mis võivad põhjustada tundlikkusega seotud probleeme"},"sound-none":{"compact":"Helidega seotud ohte pole","descriptive":"Väljaanne ei sisalda helisid, mis võivad põhjustada tundlikkusega seotud probleeme"},"sound-unknown":{"compact":"Helidega seotud ohud pole teada","descriptive":"Ei õnnestu tuvastada, kas väljaanne sisaldab helisid, mis võivad põhjustada tundlikkusega seotud probleeme"},"title":"Ohud","unknown":"Ohtude olemasolu pole teada"},"legal-considerations":{"exempt":{"compact":"Taotleb hõlbustus- ja juurdepääsupiirangute erandit teatud jurisdiktsioonides","descriptive":"See väljaanne taotleb hõlbustus- ja juurdepääsupiirangute erandit teatud jurisdiktsioonides"},"no-metadata":"Teave pole saadaval","title":"Õiguslikud kaalutlused"},"navigation":{"index":{"compact":"Indeks","descriptive":"Sisukord koos viidetega loetletud kirjetele"},"no-metadata":"Teave pole saadaval","page-navigation":{"compact":"Lehe avamine","descriptive":"Lehekülgede loend, mille kaudu saab minna trükiversiooni lehekülgedele"},"structural":{"compact":"Pealkirjad","descriptive":"Struktureeritud liikumise elemendid, nagu pealkirjad, tabelid jne"},"title":"Väljaandes liikumine","toc":{"compact":"Sisukord","descriptive":"Sisukord kõigi peatükkide juurde linkide kaudu"}},"rich-content":{"accessible-chemistry-as-latex":{"compact":"Keemiavalemid LaTeX-is","descriptive":"Keemiavalemid loetavas ja hõlbustatud vormingus (LaTeX)"},"accessible-chemistry-as-mathml":{"compact":"Keemiavalemid MathML-is","descriptive":"Keemiavalemid loetavas ja hõlbustatud vormingus (MathML)"},"accessible-math-as-latex":{"compact":"Matemaatika LaTeX-is","descriptive":"Matemaatika valemid loetavas ja hõlbustatud vormingus (LaTeX)"},"accessible-math-described":"Matemaatilisel sisu on tekstilised kirjeldused","closed-captions":{"compact":"Videotel on olemas väljalülitatavad subtiitrid","descriptive":"Väljaandes leiduvatel videotel on olemas väljalülitatavad subtiitrid"},"extended-descriptions":"Inforikastel piltidel on täiendavad kirjeldused","math-as-mathml":{"compact":"Matemaatika MathML-is","descriptive":"Matemaatilised valemid hõlbustusele ja ligipääsetavusele vastavas vormingus (MathML)"},"open-captions":{"compact":"Videotel on olemas pidevalt nähtavad subtiitrid","descriptive":"Väljaandes leiduvatel videotel on olemas pidevalt nähtavad subtiitrid"},"title":"Mitmekülgses vormis sisu","transcript":"Heli- ja videosisul on olemas tekstiline vaste","unknown":"Teave pole saadaval"},"ways-of-reading":{"nonvisual-reading":{"alt-text":{"compact":"Selgitustekstid on olemas","descriptive":"Piltidel on olemas selgitustekst (alt-tekst)"},"no-metadata":"Puudub teave mittevisuaalse lugemise võimaluste kohta","none":{"compact":"Ei ole loetav ettelugemise või dünaamilise punktkirja abil","descriptive":"Sisu ei ole loetav etteloetavana ega dünaamilise punktkirjana"},"not-fully":{"compact":"Ei ole täies mahus loetav ettelugemise või dünaamilise punktkirja abil","descriptive":"Kogu sisu ei ole loetav ettelugemise või dünaamilise punktkirja abil"},"readable":{"compact":"On loetav ettelugemise või dünaamilise punktkirja abil","descriptive":"Kogu sisu on loetav ettelugemise või dünaamilise punktkirja abil"}},"prerecorded-audio":{"complementary":{"compact":"Eelsalvestatud heliklipid","descriptive":"Sisusse on lõimitud eelsalvestatud heliklipid"},"no-metadata":"Puudub teave eelsalvestatud helilise sisu kohta","only":{"compact":"Sisu koosneb ainult lõimitud eelsalvestatud heliklippidest","descriptive":"Heliraamat ilma tekstilise alternatiivita"},"synchronized":{"compact":"Eelsalvestatud heli, mis on sünkroonis tekstilise sisuga","descriptive":"Kogu sisu on saadaval eelsalvestatud helifailina, mis on sünkroonis tekstilise sisuga"}},"title":"Lugemise viisid ja võimalused","visual-adjustments":{"modifiable":{"compact":"Välimus on muudetav","descriptive":"Teksti välimust ja lehekülje paigutust saab kohandada vastavalt lugemissüsteemi võimalustele (kirjatüüp ja selle suurus, vahed lõikude, lausete, sõnade ja tähtede vahel ning tausta ja teksti värv)"},"unknown":"Puudub teave välimuse muudetavuse kohta","unmodifiable":{"compact":"Välimust ei saa muuta","descriptive":"Teksti ja lehekülje paigutust ei saa muuta ja lugemiskogemus on sarnane või sarnane trükiversiooniga, kuid lugemisvaated võimaldavad siiski suumimist"}}}}},"altIdentifier_one":"alternatiivne tunnus","altIdentifier_other":"alternatiivset tunnust","artist_one":"kunstnik","artist_other":"kunstnikud","author_one":"kirjanik","author_other":"kirjanikud","collection_one":"toimetatud kogumik","collection_other":"toimetatud kogumikud","colorist_one":"värvija","colorist_other":"värvijad","contributor_one":"kaasautor","contributor_other":"kaasautorid","description":"kirjeldus","duration":"kestus","editor_one":"toimetaja","editor_other":"toimetajad","identifier_one":"tunnus","identifier_other":"tunnused","illustrator_one":"illustraator","illustrator_other":"illustraatorid","imprint_one":"kirjastaja kaubamärk","imprint_other":"kirjastaja kaubamärgid","inker_one":"(koomiksi) värvija","inker_other":"(koomiksi) värvijad","language_one":"keel","language_other":"keeled","letterer_one":"(koomiksi) tekstikirjutaja","letterer_other":"(koomiksi) tekstikirjutajad","modified":"muutmise kuupäev","narrator_one":"ettelugeja","narrator_other":"ettelugejad","numberOfPages":"trükise lehtede arv","penciler_one":"joonistaja","penciler_other":"joonistajad","published":"avaldamise kuupäev","publisher_one":"väljaandja","publisher_other":"väljaandjad","series_one":"sari","series_other":"sarjad","subject_one":"teema","subject_other":"teemad","subtitle":"alapealkiri","title":"pealkiri","translator_one":"tõlkija","translator_other":"tõlkijad"}}`),De={publication:Ee}})),ke=r({default:()=>je,publication:()=>Ae}),Ae,je,Me=n((()=>{Ae=JSON.parse(`{"format":{"audiobook":"Äänikirja","audiobookJSON":"Äänikirjaluettelo","cbz":"Sarjakuva-arkisto","divina":"Divina-julkaisu","divinaJSON":"Divina-julkaisuluettelo","epub":"EPUB","lcpa":"LCP-suojattu äänikirja","lcpdf":"LCP-suojattu PDF","lcpl":"LCP-lisenssi","pdf":"PDF","rwp":"Readium Web -julkaisu","rwpm":"Readium Web -julkaisuluettelo","zab":"Äänikirja-arkisto","zip":"ZIP-arkisto"},"kind":{"audiobook_one":"äänikirja","audiobook_other":"äänikirjaa","book_one":"kirja","book_other":"kirjaa","comic_one":"sarjakuva","comic_other":"sarjakuvaa","document_one":"tiedosto","document_other":"tiedostoa"},"metadata":{"accessibility":{"display-guide":{"accessibility-summary":{"no-metadata":"Tietoa ei saatavilla","publisher-contact":"Ota yhteyttä julkaisijaan, jos haluat lisää tietoa julkaisun saavutettavuudesta: ","title":"Saavutettavuuden yhteenveto"},"additional-accessibility-information":{"aria":{"compact":"ARIA-rooleja on käytetty","descriptive":"Sisältöön on lisätty ARIA-rooleja, jotka selkeyttävät rakennetta ja voivat helpottaa navigaatiota"},"audio-descriptions":"Kuvailutulkkaus","braille":"Pistekirjoitus","color-not-sole-means-of-conveying-information":"Väri ei ole ainoa keino välittää tietoa","dyslexia-readability":"Soveltuu henkilöille, joilla on lukivaikeus","full-ruby-annotations":"Kattavat rubi-merkinnät","high-contrast-between-foreground-and-background-audio":"Korkea kontrasti äänisisältöjen edusta- ja taustaäänen tasoissa","high-contrast-between-text-and-background":"Korkea kontrasti tekstin ja taustan välillä","large-print":"Isotekstinen","page-breaks":{"compact":"Sivunvaihtokohdat on merkitty","descriptive":"Painetun julkaisun sivunvaihtokohdat on merkitty"},"ruby-annotations":"Sisältää rubi-merkintöjä","sign-language":"Viittomakielinen","tactile-graphics":{"compact":"Sisältää kohokuvia","descriptive":"Sisältää kohokuvia sokeille henkilöille"},"tactile-objects":"Kolmiulotteisia taktiiliosia","text-to-speech-hinting":"Tekstistä puheeksi -vihjeitä","title":"Lisätietoa saavutettavuudesta","ultra-high-contrast-between-text-and-background":"Erittäin korkea kontrasti tekstin ja taustan välillä","visible-page-numbering":"Näkyvä sivunumerointi","without-background-sounds":"Ei taustaääniä"},"conformance":{"a":{"compact":"Tämä julkaisu noudattaa saavutettavuusstandardien alinta tasoa","descriptive":"Tämä julkaisu ilmoittaa, että se noudattaa standardeja EPUB Accessibility ja WCAG 2, taso A"},"aa":{"compact":"Tämä julkaisu noudattaa saavutettavuusstandardien yleisesti hyväksyttyä tasoa","descriptive":"Tämä julkaisu ilmoittaa, että se noudattaa standardeja EPUB Accessibility ja WCAG 2, taso AA"},"aaa":{"compact":"Tämä julkaisu ylittää saavutettavuusstandardien yleisesti hyväksytyn tason","descriptive":"Tämä julkaisu ilmoittaa, että se noudattaa standardeja EPUB Accessibility ja WCAG 2, taso AAA"},"certifier":"Julkaisun saavutettavuuden on arvioinut ","certifier-credentials":"Arvioijan sertifiointitunnus on ","details":{"certification-info":"Julkaisu on arvioitu ","certifier-report":"Lisätietoja arvioijan raportissa","claim":"Tämän julkaisun ilmoitetaan noudattavan standardia","epub-accessibility-1-0":"EPUB Accessibility 1.0","epub-accessibility-1-1":"EPUB Accessibility 1.1","level-a":"Taso A","level-aa":"Taso AA","level-aaa":"Taso AAA","wcag-2-0":{"compact":"WCAG 2.0","descriptive":"Verkkosisällön saavutettavuusohjeet (WCAG) 2.0"},"wcag-2-1":{"compact":"WCAG 2.1","descriptive":"Verkkosisällön saavutettavuusohjeet (WCAG) 2.1"},"wcag-2-2":{"compact":"WCAG 2.2","descriptive":"Verkkosisällön saavutettavuusohjeet (WCAG) 2.2"}},"details-title":"Tarkat tiedot saavutettavuusstandardien noudattamisesta","no":"Tietoa ei ole saatavilla","title":"Saavutettavuusstandardien noudattaminen","unknown-standard":"Ei ole tiedossa, noudattaako julkaisu saavutettavuusstandardeja"},"hazards":{"flashing":{"compact":"Välkkyvää sisältöä","descriptive":"Julkaisussa on välkkyvää sisältöä, joka voi olla haitallista valoherkille"},"flashing-none":{"compact":"Ei välkkyvää sisältöä","descriptive":"Julkaisussa ei ole välkkyvää sisältöä, joka voi olla haitallista valoherkille"},"flashing-unknown":{"compact":"Ei tietoa välkkyvästä sisällöstä","descriptive":"Ei ole tietoa, onko julkaisussa välkkyvää sisältöä"},"motion":{"compact":"Simuloitua liikettä","descriptive":"Julkaisu sisältää simuloitua liikettä, joka voi aiheuttaa liikepahoinvointia"},"motion-none":{"compact":"Ei simuloitua liikettä","descriptive":"Julkaisu ei sisällä simuloitua liikettä, joka voi aiheuttaa liikepahoinvointia"},"motion-unknown":{"compact":"Ei tietoa simuloidusta liikkeestä","descriptive":"Ei ole tietoa, onko julkaisussa simuloitua liikettä, joka voi aiheuttaa liikepahoinvointia"},"no-metadata":"Tietoa ei ole saatavilla","none":{"compact":"Ei vaaratekijöitä","descriptive":"Julkaisu ei sisällä vaaratekijöitä"},"sound":{"compact":"Ääniä","descriptive":"Julkaisu sisältää ääniä, jotka voivat olla häiritseviä"},"sound-none":{"compact":"Ei häiritseviä ääniä","descriptive":"Julkaisu ei sisällä häiritseviä ääniä"},"sound-unknown":{"compact":"Ei tietoa häiritsevistä äänistä","descriptive":"Ei ole tietoa, onko julkaisussa häiritseviä ääniä"},"title":"Vaaratekijät","unknown":"Ei tietoa vaaratekijöistä"},"legal-considerations":{"exempt":{"compact":"Vedotaan poikkeukseen saavutettavuusvaatimuksissa","descriptive":"Tämän julkaisun kohdalla vedotaan poikkeukseen saavutettavuusvaatimuksissa"},"no-metadata":"Tietoa ei ole saatavilla","title":"Oikeudellisia huomioita"},"navigation":{"index":{"compact":"Hakemisto","descriptive":"Hakemisto, jossa hakusanat on linkitetty sisältöön"},"no-metadata":"Tietoa ei ole saatavilla","page-navigation":{"compact":"Siirry sivulle","descriptive":"Sivuluettelo, jonka avulla voi siirtyä painetun version sivuja vastaaviin kohtiin"},"structural":{"compact":"Otsikot","descriptive":"Sisältää navigointia helpottavia rakenteita, kuten otsikoita"},"title":"Siirtyminen","toc":{"compact":"Sisällysluettelo","descriptive":"Sisällysluettelo, jossa on linkit kaikkiin lukuihin"}},"rich-content":{"accessible-chemistry-as-latex":{"compact":"Kemialliset kaavat LaTeX-muodossa","descriptive":"Kemialliset kaavat saavutettavassa muodossa (LaTeX)"},"accessible-chemistry-as-mathml":{"compact":"Kemialliset kaavat MathML-muodossa","descriptive":"Kemialliset kaavat saavutettavassa muodossa (MathML)"},"accessible-math-as-latex":{"compact":"Matematiikka LaTeX-muodossa","descriptive":"Matemaattiset kaavat saavutettavassa muodossa (LaTeX)"},"accessible-math-described":"Matematiikalle on tekstikuvaukset","closed-captions":{"compact":"Videoissa on tekstitys","descriptive":"Julkaisuihin sisältyvissä videoissa on tekstitys"},"extended-descriptions":"Paljon tietoa sisältävillä kuvilla on pitkät selostukset","math-as-mathml":{"compact":"Matematiikka MathML-muodossa","descriptive":"Matemaattiset kaavat saavutettavassa muodossa (MathML)"},"open-captions":{"compact":"Videoissa on kiinteä tekstitys","descriptive":"Julkaisuihin sisältyvissä videoissa on kiinteä tekstitys"},"title":"Monimuotoinen sisältö","transcript":"Tekstivastine ääni- tai videosisällölle","unknown":"Tietoa ei ole saatavilla"},"ways-of-reading":{"nonvisual-reading":{"alt-text":{"compact":"Sisältää vaihtoehtoiset tekstit","descriptive":"Sisältää vaihtoehtoiset tekstit kuville"},"no-metadata":"Ei tietoa tukeeko muita kuin näköön perustuvia tapoja lukea","none":{"compact":"Ei luettavissa ruudunlukuohjelmalla tai pistenäytöllä","descriptive":"Sisältö ei ole luettavissa ruudunlukuohjelmalla tai pistenäytöllä"},"not-fully":{"compact":"Ei kokonaan luettavissa ruudunlukuohjelmalla tai pistenäytöllä","descriptive":"Ei kokonaan luettavissa ruudunlukuohjelmalla tai pistenäytöllä"},"readable":{"compact":"Luettavissa ruudunlukuohjelmalla tai pistenäytöllä","descriptive":"Kaikki sisältö on luettavissa ruudunlukuohjelmalla tai pistenäytöllä"}},"prerecorded-audio":{"complementary":{"compact":"Sisältää äänitteitä","descriptive":"Sisällössä on äänitettyjä osuuksia"},"no-metadata":"Ei tietoa äänitteistä","only":{"compact":"Sisältää vain ääntä","descriptive":"Äänikirja, jossa ei ole tekstiä"},"synchronized":{"compact":"Äänite on synkronoitu tekstin kanssa","descriptive":"Koko sisältö on käytettävissä äänitteenä, joka on synkronoitu tekstin kanssa"}},"title":"Lukemisen keinot","visual-adjustments":{"modifiable":{"compact":"Ulkoasua voi mukauttaa","descriptive":"Tekstin ja sivujen ulkoasua voi mukauttaa lukuohjelman toimintojen avulla (esimerkiksi muuttaa kirjaintyyppiä, tekstin kokoa ja välistyksiä sekä tekstin ja taustan värejä)"},"unknown":"Ei tietoa siitä, voiko ulkoasua mukauttaa","unmodifiable":{"compact":"Ulkoasua ei voi mukauttaa","descriptive":"Tekstin ja sivujen ulkoasu mukailee painettua versiota eikä ulkoasua voi mukauttaa. Lukuohjelmassa voi kuitenkin olla mahdollista zoomata."}}}}},"altIdentifier_one":"vaihtoehtoinen tunniste","altIdentifier_other":"vaihtoehtoiset tunnisteet","artist_one":"taiteilija","artist_other":"taiteilijat","author_one":"kirjailija","author_other":"kirjailijat","collection_one":"toimituksellinen kirjasarja","collection_other":"toimitukselliset kirjasarjat","colorist_one":"värittäjä","colorist_other":"värittäjät","contributor_one":"avustaja","contributor_other":"avustajat","description":"kuvaus","duration":"kesto","editor_one":"toimittaja","editor_other":"toimittajat","identifier_one":"tunniste","identifier_other":"tunnisteet","illustrator_one":"kuvittaja","illustrator_other":"kuvittajat","imprint_one":"imprint-kustantamo","imprint_other":"imprint-kustantamot","inker_one":"puhtaaksipiirtäjä","inker_other":"puhtaaksipiirtäjät","language_one":"kieli","language_other":"kielet","letterer_one":"tekstaaja","letterer_other":"tekstaajat","modified":"muokkauspäivämäärä","narrator_one":"lukija","narrator_other":"lukijat","numberOfPages":"painetun kirjan sivumäärä","penciler_one":"piirtäjä","penciler_other":"piirtäjät","published":"julkaisupäivä","publisher_one":"kustantaja","publisher_other":"kustantajat","series_one":"sarja","series_other":"sarjat","subject_one":"aihe","subject_other":"aiheet","subtitle":"alaotsikko","title":"nimi","translator_one":"kääntäjä","translator_other":"kääntäjät"}}`),je={publication:Ae}})),Ne=r({default:()=>Fe,publication:()=>Pe}),Pe,Fe,Ie=n((()=>{Pe=JSON.parse(`{"format":{"audiobook":"Livre audio","audiobookJSON":"Manifeste de livre audio","cbz":"Bande dessinée","divina":"Bande dessinée Divina","divinaJSON":"Manifeste de bande dessinée Divina","epub":"EPUB","lcpa":"Livre audio protégé par LCP","lcpdf":"PDF protégé par LCP","lcpl":"Licence LCP","pdf":"PDF","rwp":"Publication web Readium","rwpm":"Manifeste de publication web Readium","zab":"Livre audio","zip":"Archive ZIP"},"kind":{"audiobook_many":"livres audio","audiobook_one":"livre audio","audiobook_other":"livres audio","book_many":"livres","book_one":"livre","book_other":"livres","comic_many":"bandes dessinées","comic_one":"bande dessinée","comic_other":"bandes dessinées","document_many":"documents","document_one":"document","document_other":"documents"},"metadata":{"accessibility":{"display-guide":{"accessibility-summary":{"no-metadata":"Aucune information disponible","publisher-contact":"Pour plus d'information à propos de l'accessibilité de cette publication, veuillez contacter l'éditeur\xA0: ","title":"Informations d'accessibilité supplémentaires fournies par l'éditeur"},"additional-accessibility-information":{"aria":{"compact":"Information enrichie pour les technologies d'assistances","descriptive":"La structure est enrichi de rôles ARIA afin d'optimiser l'organisation et de faciliter la navigation via les technologies d'assistances"},"audio-descriptions":"Description audio","braille":"Braille","color-not-sole-means-of-conveying-information":"La couleur n'est pas la seule manière de communiquer de l'information","dyslexia-readability":"Lisibilité adapté aux publics dys","full-ruby-annotations":"Annotations complètes au format ruby (langues asiatiques)","high-contrast-between-foreground-and-background-audio":"Contraste sonore amélioré entre les différents plans","high-contrast-between-text-and-background":"Contraste élevé entre le texte et l'arrière-plan","large-print":"Grands caractères","page-breaks":{"compact":"Pagination identique à l'imprimé","descriptive":"Contient une pagination identique à la version imprimée"},"ruby-annotations":"Annotations partielles au format ruby (langues asiatiques)","sign-language":"Langue des signes","tactile-graphics":{"compact":"Graphiques tactiles","descriptive":"Des graphiques tactiles ont été intégrés pour faciliter l'accès des personnes aveugles aux éléments visuels"},"tactile-objects":"Objets 3D ou tactiles","text-to-speech-hinting":"Prononciation améliorée pour la synthèse vocale","title":"Informations complémentaires sur l'accessibilité","ultra-high-contrast-between-text-and-background":"Contraste très élevé entre le texte et l'arrière-plan","visible-page-numbering":"Numérotation de page visible","without-background-sounds":"Aucun bruit de fond"},"conformance":{"a":{"compact":"Cette publication répond aux règles minimales d'accessibilité","descriptive":"La publication indique qu'elle respecte les règles d'accessibilité EPUB et WCAG 2 niveau A"},"aa":{"compact":"Cette publication répond aux règles d'accessibilité reconnues","descriptive":"La publication indique qu'elle respecte les règles d'accessibilité EPUB et WCAG 2 niveau AA"},"aaa":{"compact":"Cette publication dépasse les règles d'accessibilité reconnues","descriptive":"La publication indique qu'elle respecte les règles d'accessibilité EPUB et WCAG 2 niveau AAA"},"certifier":"Accessibilité évaluée par ","certifier-credentials":"L'évaluateur est accrédité par ","details":{"certification-info":"Cette publication a été certifié le","certifier-report":"Pour plus d'information, veuillez consulter le rapport de certification","claim":"Cette publication indique respecter","epub-accessibility-1-0":"EPUB Accessibilité 1.0","epub-accessibility-1-1":"EPUB Accessibilité 1.1","level-a":"Niveau A","level-aa":"Niveau AA","level-aaa":"Niveau AAA","wcag-2-0":{"compact":"WCAG 2.0","descriptive":"Règles pour l’accessibilité des contenus Web (WCAG) 2.0"},"wcag-2-1":{"compact":"WCAG 2.1","descriptive":"Règles pour l’accessibilité des contenus Web (WCAG) 2.1"},"wcag-2-2":{"compact":"WCAG 2.2","descriptive":"Règles pour l’accessibilité des contenus Web (WCAG) 2.2"}},"details-title":"Information détaillée","no":"Aucune information disponible","title":"Règles d'accessibilité","unknown-standard":"Aucune indication concernant les normes d'accessibilité"},"hazards":{"flashing":{"compact":"Flashs lumineux","descriptive":"La publication contient des flashs lumineux qui peuvent provoquer des crises d’épilepsie"},"flashing-none":{"compact":"Pas de flashs lumineux","descriptive":"La publication ne contient pas de flashs lumineux susceptibles de provoquer des crises d’épilepsie"},"flashing-unknown":{"compact":"Pas d'information concernant la présence de flashs lumineux","descriptive":"La présence de flashs lumineux susceptibles de provoquer des crises d’épilepsie n'a pas pu être déterminée"},"motion":{"compact":"Sensations de mouvement","descriptive":"La publication contient des images en mouvement qui peuvent provoquer des nausées, des vertiges et des maux de tête"},"motion-none":{"compact":"Pas de sensations de mouvement","descriptive":"La publication ne contient pas d'images en mouvement qui pourraient provoquer des nausées, des vertiges et des maux de tête"},"motion-unknown":{"compact":"Pas d'information concernant la présence d'images en mouvement","descriptive":"La présence d'images en mouvement susceptibles de provoquer des nausées, des vertiges et des maux de tête n'a pas pu être déterminée"},"no-metadata":"Aucune information disponible","none":{"compact":"Aucun points d'attention","descriptive":"La publication ne présente aucun risque lié à la présence de flashs lumineux, de sensations de mouvement ou de sons"},"sound":{"compact":"Sons","descriptive":"La publication contient des sons qui peuvent causer des troubles de la sensibilité"},"sound-none":{"compact":"Pas de risques sonores","descriptive":"La publication ne contient pas de sons susceptibles de provoquer des troubles de la sensibilité"},"sound-unknown":{"compact":"Pas d'information concernant la présence de sons","descriptive":"La présence de sons susceptibles de causer des troubles de sensibilité n'a pas pu être déterminée"},"title":"Points d'attention","unknown":"La présence de risques est inconnue"},"legal-considerations":{"exempt":{"compact":"Déclare être sous le coup d'une exemption dans certaines juridictions","descriptive":"Cette publication déclare être sous le coup d'une exemption dans certaines juridictions"},"no-metadata":"Aucune information disponible","title":"Considérations légales"},"navigation":{"index":{"compact":"Index","descriptive":"Index comportant des liens vers les entrées référencées"},"no-metadata":"Aucune information disponible","page-navigation":{"compact":"Aller à la page","descriptive":"Permet d'accéder aux pages de la version source imprimée"},"structural":{"compact":"Titres","descriptive":"Contient des titres pour une navigation structurée"},"title":"Points de repère","toc":{"compact":"Table des matières","descriptive":"Table des matières"}},"rich-content":{"accessible-chemistry-as-latex":{"compact":"Formules chimiques en LaTeX","descriptive":"Formules chimiques en format accessible (LaTeX)"},"accessible-chemistry-as-mathml":{"compact":"Formules chimiques en MathML","descriptive":"Formules chimiques en format accessible (MathML)"},"accessible-math-as-latex":{"compact":"Mathématiques en LaTeX","descriptive":"Formules mathématiques en format accessible (LaTeX)"},"accessible-math-described":"Des descriptions textuelles des formules mathématiques sont fournies","closed-captions":{"compact":"Sous-titres disponibles pour les vidéos","descriptive":"Des sous titres sont disponibles pour les vidéos"},"extended-descriptions":"Les images porteuses d'informations complexes sont décrites par des descriptions longues","math-as-mathml":{"compact":"Mathématiques en MathML","descriptive":"Formules mathématiques en format accessible (MathML)"},"open-captions":{"compact":"Sous-titres incrustés","descriptive":"Des sous titres sont incrustés pour les vidéos"},"title":"Contenus spécifiques","transcript":"Transcriptions fournies","unknown":"Aucune information disponible"},"ways-of-reading":{"nonvisual-reading":{"alt-text":{"compact":"Images décrites","descriptive":"Les images sont décrites par un texte"},"no-metadata":"Aucune information pour la lecture en voix de synthèse ou en braille","none":{"compact":"Non lisible en voix de synthèse ou en braille","descriptive":"Le contenu n'est pas lisible en voix de synthèse ou en braille"},"not-fully":{"compact":"Pas entièrement lisible en voix de synthèse ou en braille","descriptive":"Tous les contenus ne pourront pas être lus à haute voix ou en braille"},"readable":{"compact":"Entièrement lisible en voix de synthèse ou en braille","descriptive":"Tous les contenus peuvent être lus en voix de synthèse ou en braille"}},"prerecorded-audio":{"complementary":{"compact":"Clips audio préenregistrés","descriptive":"Des clips audio préenregistrés sont intégrés au contenu"},"no-metadata":"Aucune information sur les enregistrements audio","only":{"compact":"Audio préenregistré uniquement","descriptive":"Livre audio sans texte alternatif"},"synchronized":{"compact":"Audio préenregistré synchronisé avec du texte","descriptive":"Tous les contenus sont disponibles comme audio préenregistrés synchronisés avec le texte"}},"title":"Lisibilité","visual-adjustments":{"modifiable":{"compact":"L'affichage peut être adapté","descriptive":"L'apparence du texte et la mise en page peuvent être modifiées en fonction des capacités du système de lecture (famille et taille des polices, espaces entre les paragraphes, les phrases, les mots et les lettres, ainsi que la couleur de l'arrière-plan et du texte)"},"unknown":"Aucune information sur les possibilités d'adaptation de l'affichage","unmodifiable":{"compact":"L'affichage ne peut pas être adapté","descriptive":"Le texte et la mise en page ne peuvent pas être adaptés étant donné que l'expérience de lecture est proche de celle de la version imprimée, mais l'application de lecture peut tout de même proposer la capacité de zoomer"}}}}},"altIdentifier_many":"","altIdentifier_one":"identifiant alternatif","altIdentifier_other":"identifiants alternatifs","artist_many":"","artist_one":"artiste","artist_other":"artiste","author_many":"","author_one":"auteur","author_other":"auteurs","collection_many":"","collection_one":"collection éditoriale","collection_other":"collections éditoriales","colorist_many":"","colorist_one":"coloriste","colorist_other":"coloristes","contributor_many":"","contributor_one":"contributeur","contributor_other":"contributeurs","description":"description","duration":"durée","editor_many":"","editor_one":"éditeur","editor_other":"éditeurs","identifier_many":"","identifier_one":"identifiant","identifier_other":"identifiants","illustrator_many":"","illustrator_one":"illustrateur","illustrator_other":"illustrateurs","imprint_many":"","imprint_one":"marque éditoriale","imprint_other":"marques éditoriales","inker_many":"","inker_one":"encreur","inker_other":"encreurs","language_many":"","language_one":"langue","language_other":"langues","letterer_many":"","letterer_one":"lettreur","letterer_other":"lettreurs","modified":"date de modification","narrator_many":"","narrator_one":"narrateur","narrator_other":"narrateurs","numberOfPages":"pagination papier","penciler_many":"","penciler_one":"dessinateur","penciler_other":"dessinateurs","published":"date de publication","publisher_many":"","publisher_one":"éditeur","publisher_other":"éditeurs","series_many":"","series_one":"série","series_other":"séries","subject_many":"","subject_one":"catégorie","subject_other":"catégories","subtitle":"sous-titre","title":"titre","translator_many":"","translator_one":"traducteur","translator_other":"traducteurs"}}`),Fe={publication:Pe}})),Le=r({default:()=>ze,publication:()=>Re}),Re,ze,Be=n((()=>{Re=JSON.parse(`{"format":{"audiobook":"Audiolibro","audiobookJSON":"Audiobook Manifest","cbz":"Comic book archive","divina":"Divina Publication","divinaJSON":"Divina Publication Manifest","epub":"EPUB","lcpa":"Audiolibro protetto con LCP","lcpdf":"PDF protetto con LCP","lcpl":"Licenza LCP","pdf":"PDF","rwp":"Readium Web Publication","rwpm":"Readium Web Publication Manifest","zab":"Audiobook Archive","zip":"ZIP Archive"},"kind":{"audiobook_many":"audiolibri","audiobook_one":"audiolibro","audiobook_other":"audiolibri","book_many":"libri","book_one":"libro","book_other":"libri","comic_many":"fumetti","comic_one":"fumetto","comic_other":"fumetti","document_many":"documenti","document_one":"documento","document_other":"documenti"},"metadata":{"accessibility":{"display-guide":{"accessibility-summary":{"no-metadata":"Nessuna informazione disponibile","publisher-contact":"Per ulteriori informazioni sull'accessibilità di questa risorsa, contattare l'editore: ","title":"Informazioni aggiuntive sull'accessibilità fornite dall'editore"},"additional-accessibility-information":{"aria":{"compact":"Ruoli ARIA inclusi","descriptive":"Il contenuto è semanticamente arricchito con ruoli ARIA per ottimizzare l'organizzazione e facilitare la navigazione"},"audio-descriptions":"Descrizioni audio","braille":"Braille","color-not-sole-means-of-conveying-information":"Il colore non è l'unico mezzo per trasmettere informazioni","dyslexia-readability":"Leggibilità adatta alla dislessia","full-ruby-annotations":"Annotazioni complete in Ruby","high-contrast-between-foreground-and-background-audio":"Elevato contrasto tra audio principale e sottofondo","high-contrast-between-text-and-background":"Contrasto elevato tra testo in primo piano e sfondo","large-print":"Stampa a caratteri ingranditi","page-breaks":{"compact":"Interruzioni di pagina incluse","descriptive":"Interruzioni di pagina identiche alla versione originale a stampa"},"ruby-annotations":"Alcune annotazioni in Ruby","sign-language":"Lingua dei segni","tactile-graphics":{"compact":"Grafica tattile inclusa","descriptive":"La grafica tattile è stata integrata per facilitare l'accesso agli elementi visivi alle persone non vedenti"},"tactile-objects":"Oggetti 3D tattili","text-to-speech-hinting":"Pronuncia migliorata per la sintesi vocale","title":"Ulteriori informazioni sull'accessibilità","ultra-high-contrast-between-text-and-background":"Contrasto molto elevato tra testo e sfondo","visible-page-numbering":"Numerazione delle pagine visibile","without-background-sounds":"Nessun suono in sottofondo"},"conformance":{"a":{"compact":"Questa pubblicazione soddisfa gli standard minimi di accessibilità","descriptive":"La pubblicazione contiene una dichiarazione di conformità che attesta il rispetto degli standard EPUB Accessibility e WCAG 2 Livello A"},"aa":{"compact":"Questa pubblicazione soddisfa gli standard di accessibilità accettati","descriptive":"La pubblicazione contiene una dichiarazione di conformità che attesta il rispetto degli standard EPUB Accessibility e WCAG 2 Livello AA"},"aaa":{"compact":"Questa pubblicazione supera gli standard di accessibilità","descriptive":"La pubblicazione contiene una dichiarazione di conformità che attesta il rispetto degli standard EPUB Accessibility e WCAG 2 Livello AAA"},"certifier":"La pubblicazione è stata certificata da ","certifier-credentials":"Le credenziali del certificatore sono ","details":{"certification-info":"La pubblicazione è stata certificata il ","certifier-report":"Per ulteriori informazioni, consultare il rapporto d'accessibilità del certificatore","claim":"Questa pubblicazione è conforme ai requisiti di","epub-accessibility-1-0":"EPUB Accessibility 1.0","epub-accessibility-1-1":"EPUB Accessibility 1.1","level-a":"Livello A","level-aa":"Livello AA","level-aaa":"Livello AAA","wcag-2-0":{"compact":"WCAG 2.0","descriptive":"Linee guida per l'accessibilità dei contenuti web (WCAG) 2.0"},"wcag-2-1":{"compact":"WCAG 2.1","descriptive":"Linee guida per l'accessibilità dei contenuti web (WCAG) 2.1"},"wcag-2-2":{"compact":"WCAG 2.2","descriptive":"Linee guida per l'accessibilità dei contenuti web (WCAG) 2.2"}},"details-title":"Informazioni dettagliate sulla conformità","no":"Nessuna informazione disponibile","title":"Conformità","unknown-standard":"Nessuna indicazione sugli standard d'accessibilità"},"hazards":{"flashing":{"compact":"Contenuto lampeggiante","descriptive":"La pubblicazione contiene contenuti lampeggianti che possono causare crisi d'epilessia fotosensibile"},"flashing-none":{"compact":"Nessun contenuto lampeggiante","descriptive":"La pubblicazione non presenta contenuti lampeggianti che possono causare crisi d'epilessia fotosensibile"},"flashing-unknown":{"compact":"Nessuna informazione sulla presenza di contenuti lampeggianti","descriptive":"Non è stato possibile determinare la presenza di contenuti lampeggianti che possono causare crisi d'epilessia fotosensibile"},"motion":{"compact":"Simulazione del movimento","descriptive":"La pubblicazione contiene simulazioni di movimento che possono provocare cinetosi"},"motion-none":{"compact":"Nessun rischio di simulazione del movimento","descriptive":"La pubblicazione non contiene simulazioni di movimento che possono causare la cinetosi"},"motion-unknown":{"compact":"Nessuna informazione relativa alla presenza di simulazioni di movimento","descriptive":"Non è stato possibile determinare la presenza di contenuti che possono provocare cinetosi"},"no-metadata":"Nessuna informazione disponibile","none":{"compact":"Nessuna problematica","descriptive":"La pubblicazione non presenta contenuti a rischio di simulazione di movimento, di suoni, o di contenuti lampeggianti"},"sound":{"compact":"Suoni","descriptive":"La pubblicazione contiene suoni che possono causare problemi di sensibilità"},"sound-none":{"compact":"Nessun rischio acustico","descriptive":"La pubblicazione non contiene suoni che possono causare problemi di sensibilità"},"sound-unknown":{"compact":"Nessuna informazione sulla presenza di suoni","descriptive":"Non è stato possibile determinare la presenza di suoni che potrebbero causare problemi di sensibilità"},"title":"Problematiche","unknown":"La presenza di rischi è sconosciuta"},"legal-considerations":{"exempt":{"compact":"Dichiara di godere dell'esenzione d'accessibilità in alcune giurisdizioni","descriptive":"Questa risorsa gode dell'esenzione d'accessibilità in alcune giurisdizioni"},"no-metadata":"Nessuna informazione disponibile","title":"Note legali"},"navigation":{"index":{"compact":"Indice analitico interattivo","descriptive":"Indice analitico con link alle voci di riferimento"},"no-metadata":"Nessuna informazione disponibile","page-navigation":{"compact":"Vai alla pagina","descriptive":"Sono presenti i riferimenti ai numeri di pagina della versione a stampa corrispondente"},"structural":{"compact":"Intestazioni","descriptive":"Contiene elementi come titoli, elenchi e tabelle per permettere una navigazione strutturata"},"title":"Navigazione","toc":{"compact":"Indice interattivo","descriptive":"L’indice permette l’accesso diretto a tutti i capitoli tramite link"}},"rich-content":{"accessible-chemistry-as-latex":{"compact":"Formule chimiche in LaTeX","descriptive":"Formule chimiche in formato accessibile (LaTeX)"},"accessible-chemistry-as-mathml":{"compact":"Formule chimiche in MathML","descriptive":"Formule chimiche in formato accessibile (MathML)"},"accessible-math-as-latex":{"compact":"Matematica in LaTeX","descriptive":"Formule matematiche in formato accessibile (LaTeX)"},"accessible-math-described":"Sono disponibili descrizioni testuali per le formule matematiche","closed-captions":{"compact":"Sottotitoli disponibili per i video","descriptive":"Per i video sono disponibili dei sottotitoli"},"extended-descriptions":"Le immagini complesse presentano descrizioni estese","math-as-mathml":{"compact":"Matematica in MathML","descriptive":"Formule matematiche in formato accessibile (MathML)"},"open-captions":{"compact":"I video hanno i sottotitoli","descriptive":"I video inclusi nella pubblicazione hanno i sottotitoli"},"title":"Contenuti arricchiti","transcript":"Trascrizioni fornite","unknown":"Nessuna informazione disponibile"},"ways-of-reading":{"nonvisual-reading":{"alt-text":{"compact":"Immagini descritte","descriptive":"Le immagini sono descritte da un testo"},"no-metadata":"Nessuna informazione sulla lettura non visiva","none":{"compact":"Non leggibile con lettura ad alta voce o in braille","descriptive":"Il contenuto non è leggibile con la lettura ad alta voce o in braille"},"not-fully":{"compact":"Non è interamente leggibile con lettura ad alta voce o in braille","descriptive":"Non tutti i contenuti potranno essere letti con lettura ad alta voce o in braille"},"readable":{"compact":"Interamente leggibile con lettura ad alta voce o in braille","descriptive":"Tutti i contenuti possono essere letti con la lettura ad alta voce o con il display braille"}},"prerecorded-audio":{"complementary":{"compact":"Clip audio preregistrate","descriptive":"Le clip audio preregistrate sono integrate nel contenuto"},"no-metadata":"Non sono disponibili informazioni sull'audio preregistrato","only":{"compact":"Solo audio preregistrato","descriptive":"Audiolibro senza testi alternativi"},"synchronized":{"compact":"Audio preregistrato sincronizzato con il testo","descriptive":"Tutti i contenuti sono disponibili come audio preregistrato sincronizzato con il testo"}},"title":"Leggibilità","visual-adjustments":{"modifiable":{"compact":"La formattazione del testo e il layout della pagina possono essere modificati","descriptive":"La formattazione del testo e il layout della pagina possono essere modificati in base alle funzionalità presenti nella soluzione di lettura (ingrandimento dei caratteri del testo, modifica dei colori e dei contrasti per il testo e lo sfondo, modifica degli spazi tra lettere, parole, frasi e paragrafi)"},"unknown":"Non sono disponibili informazioni sulla possibilità di formattare il testo","unmodifiable":{"compact":"La formattazione del testo e il display della pagina non possono essere modificati","descriptive":"Il layout del testo e della pagina non può essere modificato poiché l'esperienza di lettura è simile a una versione di stampa, ma i sistemi di lettura possono ancora fornire opzioni di zoom"}}}}},"altIdentifier_many":"identificatori alternativi","altIdentifier_one":"identificatore alternativo","altIdentifier_other":"identificatori alternativi","artist_many":"artisti","artist_one":"artista","artist_other":"artisti","author_many":"autori","author_one":"autore","author_other":"autori","collection_many":"collane","collection_one":"collana","collection_other":"collane","colorist_many":"coloristi","colorist_one":"colorista","colorist_other":"coloristi","contributor_many":"contributori","contributor_one":"contributore","contributor_other":"contributori","description":"descrizione","duration":"durata","editor_many":"editor","editor_one":"editor","editor_other":"editor","identifier_many":"identificatori","identifier_one":"identificatore","identifier_other":"identificatori","illustrator_many":"illustratori","illustrator_one":"illustratore","illustrator_other":"illustratori","imprint_many":"marche editoriali","imprint_one":"marca editoriale","imprint_other":"marche editoriali","inker_many":"inchiostratori","inker_one":"inchiostratore","inker_other":"inchiostratori","language_many":"lingue","language_one":"lingua","language_other":"lingue","letterer_many":"letteristi","letterer_one":"letterista","letterer_other":"letteristi","modified":"Data di modifica","narrator_many":"narratori","narrator_one":"narratore","narrator_other":"narratori","numberOfPages":"impaginazione versione cartacea","penciler_many":"disegnatori","penciler_one":"disegnatore","penciler_other":"disegnatori","published":"Data di pubblicazione","publisher_many":"editori","publisher_one":"editore","publisher_other":"editori","series_many":"serie","series_one":"serie","series_other":"serie","subject_many":"categorie","subject_one":"categoria","subject_other":"categorie","subtitle":"sottotitolo","title":"titolo","translator_many":"traduttori","translator_one":"traduttore","translator_other":"traduttori"}}`),ze={publication:Re}})),Ve=r({default:()=>Ue,publication:()=>He}),He,Ue,We=n((()=>{He=JSON.parse(`{"format":{"audiobook":"Audiobook","audiobookJSON":"Manifest audiobooka","cbz":"Archiwum komiksów","divina":"Publikacja Divina","divinaJSON":"Manifest publikacji Divina","epub":"EPUB","lcpa":"Audiobook chroniony przez LCP","lcpdf":"PDF chroniony przez LCP","lcpl":"Dokument licencji LCP","pdf":"PDF","rwp":"Publikacja internetowa Readium","rwpm":"Manifest publikacji internetowej Readium","zab":"Archiwum audiobooka","zip":"Archiwum ZIP"},"kind":{"audiobook_few":"audiobooki","audiobook_many":"audiobooków","audiobook_one":"audiobook","book_few":"książki","book_many":"książek","book_one":"książka","comic_few":"komiksy","comic_many":"komiksów","comic_one":"komiks","document_few":"dokumenty","document_many":"dokumentów","document_one":"dokument"},"metadata":{"accessibility":{"display-guide":{"accessibility-summary":{"no-metadata":"Brak dostępnych informacji","publisher-contact":"Aby uzyskać więcej informacji na temat dostępności tego produktu, prosimy o kontakt z wydawcą: ","title":"Podsumowanie dostępności"},"additional-accessibility-information":{"aria":{"compact":"Role ARIA uwzględnione","descriptive":"Treść jest wzbogacona o role ARIA w celu optymalizacji organizacji i ułatwienia nawigacji"},"audio-descriptions":"Audiodeskrypcja","braille":"Brajl","color-not-sole-means-of-conveying-information":"Kolor nie jest jedynym środkiem przekazywania informacji","dyslexia-readability":"Czytelność dla dyslektyków","full-ruby-annotations":"Pełne adnotacje ruby","high-contrast-between-foreground-and-background-audio":"Wysoki kontrast między dźwiękami pierwszego i drugiego planu","high-contrast-between-text-and-background":"Wysoki kontrast między tekstem a tłem","large-print":"Duży druk","page-breaks":{"compact":"Podziały stron uwzględnione","descriptive":"Podziały stron uwzględnione z oryginalnego źródła drukowanego"},"ruby-annotations":"Niektóre adnotacje ruby","sign-language":"Język migowy","tactile-graphics":{"compact":"Grafika dotykowa uwzględniona","descriptive":"Zintegrowano grafikę dotykową, aby ułatwić dostęp do elementów wizualnych osobom niewidomym"},"tactile-objects":"Dotykowe obiekty 3D","text-to-speech-hinting":"Wskazówki zamiany tekstu na mowę są dostępne","title":"Dodatkowe informacje o dostępności","ultra-high-contrast-between-text-and-background":"Ultra wysoki kontrast między tekstem a tłem","visible-page-numbering":"Widoczna numeracja stron","without-background-sounds":"Bez dźwięków tła"},"conformance":{"a":{"compact":"Ta publikacja spełnia minimalne standardy dostępności","descriptive":"Publikacja zawiera oświadczenie o zgodności ze standardem EPUB Accessibility i WCAG 2 na poziomie A"},"aa":{"compact":"Ta publikacja spełnia przyjęte standardy dostępności","descriptive":"Publikacja zawiera oświadczenie o zgodności ze standardem EPUB Accessibility i WCAG 2 na poziomie AA"},"aaa":{"compact":"Ta publikacja przekracza przyjęte standardy dostępności","descriptive":"Publikacja zawiera oświadczenie o zgodności ze standardem EPUB Accessibility i WCAG 2 na poziomie AAA"},"certifier":"Publikacja została certyfikowana przez ","certifier-credentials":"Dane uwierzytelniające certyfikatora to ","details":{"certification-info":"Publikacja została certyfikowana dnia ","certifier-report":"Aby uzyskać więcej informacji, zapoznaj się z raportem certyfikatora","claim":"Ta publikacja deklaruje spełnienie","epub-accessibility-1-0":"EPUB Accessibility 1.0","epub-accessibility-1-1":"EPUB Accessibility 1.1","level-a":"Poziom A","level-aa":"Poziom AA","level-aaa":"Poziom AAA","wcag-2-0":{"compact":"WCAG 2.0","descriptive":"Wytyczne dotyczące dostępności treści internetowych (WCAG) 2.0"},"wcag-2-1":{"compact":"WCAG 2.1","descriptive":"Wytyczne dotyczące dostępności treści internetowych (WCAG) 2.1"},"wcag-2-2":{"compact":"WCAG 2.2","descriptive":"Wytyczne dotyczące dostępności treści internetowych (WCAG) 2.2"}},"details-title":"Szczegółowe informacje o zgodności","no":"Brak dostępnych informacji","title":"Zgodność","unknown-standard":"Nie można określić zgodności tej publikacji z przyjętymi standardami dostępności"},"hazards":{"flashing":{"compact":"Migające treści","descriptive":"Publikacja zawiera migające treści mogące powodować napady fotosensytywne"},"flashing-none":{"compact":"Brak migających treści","descriptive":"Publikacja nie zawiera migających treści mogących powodować napady fotosensytywne"},"flashing-unknown":{"compact":"Obecność migających treści nieznana","descriptive":"Nie można określić obecności migających treści mogących powodować napady fotosensytywne"},"motion":{"compact":"Symulacja ruchu","descriptive":"Publikacja zawiera symulacje ruchu mogące powodować chorobę lokomocyjną"},"motion-none":{"compact":"Brak symulacji ruchu","descriptive":"Publikacja nie zawiera symulacji ruchu mogących powodować chorobę lokomocyjną"},"motion-unknown":{"compact":"Obecność symulacji ruchu nieznana","descriptive":"Nie można określić obecności symulacji ruchu mogących powodować chorobę lokomocyjną"},"no-metadata":"Brak dostępnych informacji","none":{"compact":"Brak zagrożeń","descriptive":"Publikacja nie zawiera zagrożeń"},"sound":{"compact":"Dźwięki","descriptive":"Publikacja zawiera dźwięki mogące powodować problemy z wrażliwością"},"sound-none":{"compact":"Brak zagrożeń dźwiękowych","descriptive":"Publikacja nie zawiera dźwięków mogących powodować problemy z wrażliwością"},"sound-unknown":{"compact":"Obecność zagrożeń dźwiękowych nieznana","descriptive":"Nie można określić obecności dźwięków mogących powodować problemy z wrażliwością"},"title":"Zagrożenia","unknown":"Obecność zagrożeń jest nieznana"},"legal-considerations":{"exempt":{"compact":"Zgłasza zwolnienie z wymogów dostępności w niektórych jurysdykcjach","descriptive":"Ta publikacja zgłasza zwolnienie z wymogów dostępności w niektórych jurysdykcjach"},"no-metadata":"Brak dostępnych informacji","title":"Kwestie prawne"},"navigation":{"index":{"compact":"Indeks","descriptive":"Indeks z odnośnikami do przywołanych pozycji"},"no-metadata":"Brak dostępnych informacji","page-navigation":{"compact":"Przejdź do strony","descriptive":"Lista stron umożliwiająca przejście do stron z wersji drukowanej"},"structural":{"compact":"Nagłówki","descriptive":"Elementy takie jak nagłówki, tabele itp. do nawigacji strukturalnej"},"title":"Nawigacja","toc":{"compact":"Spis treści","descriptive":"Spis treści do wszystkich rozdziałów tekstu za pomocą odnośników"}},"rich-content":{"accessible-chemistry-as-latex":{"compact":"Wzory chemiczne w LaTeX","descriptive":"Wzory chemiczne w dostępnym formacie (LaTeX)"},"accessible-chemistry-as-mathml":{"compact":"Wzory chemiczne w MathML","descriptive":"Wzory chemiczne w dostępnym formacie (MathML)"},"accessible-math-as-latex":{"compact":"Matematyka w LaTeX","descriptive":"Wzory matematyczne w dostępnym formacie (LaTeX)"},"accessible-math-described":"Dostępne są tekstowe opisy wzorów matematycznych","closed-captions":{"compact":"Filmy mają napisy ukryte","descriptive":"Filmy zawarte w publikacji mają napisy ukryte"},"extended-descriptions":"Bogate w informacje obrazy są opisane za pomocą rozszerzonych opisów","math-as-mathml":{"compact":"Matematyka w MathML","descriptive":"Wzory matematyczne w dostępnym formacie (MathML)"},"open-captions":{"compact":"Filmy mają napisy otwarte","descriptive":"Filmy zawarte w publikacji mają napisy otwarte"},"title":"Bogate treści","transcript":"Dostępny transkrypt(y)","unknown":"Brak dostępnych informacji"},"ways-of-reading":{"nonvisual-reading":{"alt-text":{"compact":"Posiada tekst alternatywny","descriptive":"Posiada alternatywne opisy tekstowe dla obrazów"},"no-metadata":"Brak informacji o czytaniu niewizuwalnym","none":{"compact":"Niedostępne do odczytu głosowego lub dynamicznego brajla","descriptive":"Treść nie jest dostępna jako mowa odczytywana na głos ani dynamiczny brajl"},"not-fully":{"compact":"Nie w pełni dostępne do odczytu głosowego lub dynamicznego brajla","descriptive":"Nie cała treść będzie dostępna jako mowa odczytywana na głos lub dynamiczny brajl"},"readable":{"compact":"Dostępne do odczytu głosowego lub dynamicznego brajla","descriptive":"Cała treść może być odczytana jako mowa odczytywana na głos lub dynamiczny brajl"}},"prerecorded-audio":{"complementary":{"compact":"Nagrania audio","descriptive":"Nagrania audio są osadzone w treści"},"no-metadata":"Brak informacji o nagraniach audio","only":{"compact":"Tylko nagrania audio","descriptive":"Audiobook bez alternatywy tekstowej"},"synchronized":{"compact":"Nagrania audio zsynchronizowane z tekstem","descriptive":"Cała treść jest dostępna jako nagrania audio zsynchronizowane z tekstem"}},"title":"Sposoby czytania","visual-adjustments":{"modifiable":{"compact":"Wygląd można modyfikować","descriptive":"Wygląd tekstu i układ strony można modyfikować zgodnie z możliwościami systemu czytania (rodzina i rozmiar czcionki, odstępy między akapitami, zdaniami, słowami i literami, a także kolor tła i tekstu)"},"unknown":"Brak informacji o możliwości modyfikacji wyglądu","unmodifiable":{"compact":"Wygląd nie może być modyfikowany","descriptive":"Tekstu i układu strony nie można modyfikować, ponieważ doświadczenie czytania jest zbliżone do wersji drukowanej, ale systemy czytania mogą nadal udostępniać opcje powiększania"}}}}},"altIdentifier_few":"alternatywne identyfikatory","altIdentifier_many":"alternatywnych identyfikatorów","altIdentifier_one":"alternatywny identyfikator","artist_few":"artystów","artist_many":"artystów","artist_one":"artysta","author_few":"autorów","author_many":"autorów","author_one":"autor","collection_few":"kolekcje redakcyjne","collection_many":"kolekcji redakcyjnych","collection_one":"kolekcja redakcyjna","colorist_few":"kolorystów","colorist_many":"kolorystów","colorist_one":"kolorzysta","contributor_few":"współtwórców","contributor_many":"współtwórców","contributor_one":"współtwórca","description":"opis","duration":"czas trwania","editor_few":"redaktorów","editor_many":"redaktorów","editor_one":"redaktor","identifier_few":"identyfikatory","identifier_many":"identyfikatorów","identifier_one":"identyfikator","illustrator_few":"ilustratorów","illustrator_many":"ilustratorów","illustrator_one":"ilustrator","imprint_few":"wydawnictwa","imprint_many":"wydawnictw","imprint_one":"wydawnictwo","inker_few":"tuszowników","inker_many":"tuszowników","inker_one":"tuszownik","language_few":"języki","language_many":"języków","language_one":"język","letterer_few":"literników","letterer_many":"literników","letterer_one":"liternik","modified":"data modyfikacji","narrator_few":"narratorów","narrator_many":"narratorów","narrator_one":"narrator","numberOfPages":"liczba stron","penciler_few":"rysowników","penciler_many":"rysowników","penciler_one":"rysownik","published":"data publikacji","publisher_few":"wydawców","publisher_many":"wydawców","publisher_one":"wydawca","series_few":"serie","series_many":"serii","series_one":"seria","subject_few":"tematy","subject_many":"tematów","subject_one":"temat","subtitle":"podtytuł","title":"tytuł","translator_few":"tłumaczy","translator_many":"tłumaczy","translator_one":"tłumacz"}}`),Ue={publication:He}})),Ge=r({default:()=>qe,publication:()=>Ke}),Ke,qe,Je=n((()=>{Ke=JSON.parse(`{"format":{"audiobook":"Audiobook","audiobookJSON":"Manifesto do livro áudio","cbz":"Banda desenhada","divina":"Publicação Divina","divinaJSON":"Manifesto de publicação Divina","epub":"EPUB","pdf":"PDF","rwp":"Documento Web do Readium","zab":"Ficheiro Audiobook","zip":"Ficheiro ZIP"},"kind":{"audiobook_many":"Livros áudio","audiobook_one":"Livro áudio","audiobook_other":"Livros áudio","book_many":"livros","book_one":"livro","book_other":"livros","comic_many":"Bandas desenhadas","comic_one":"Banda desenhada","comic_other":"Bandas desenhadas","document_many":"documentos","document_one":"documento","document_other":"documentos"},"metadata":{"accessibility":{"display-guide":{"accessibility-summary":{"no-metadata":"Sem informação disponível","publisher-contact":"Para mais informações sobre a acessibilidade deste produto, contacte a editora: ","title":"Resumo de acessibilidade"},"additional-accessibility-information":{"aria":{"compact":"Inclui funções ARIA","descriptive":"O conteúdo foi otimizado com funções ARIA para melhorar a organização e facilitar a navegação"},"audio-descriptions":"Descrições de áudio","braille":"Braille","color-not-sole-means-of-conveying-information":"A cor não é o único meio de transmitir informação","dyslexia-readability":"Otimizado para dislexia","full-ruby-annotations":"Anotações Ruby completas","high-contrast-between-foreground-and-background-audio":"Alto contraste entre som principal e fundo","high-contrast-between-text-and-background":"Alto contraste entre texto e fundo","large-print":"Impressão ampliada","page-breaks":{"compact":"Quebras de página incluídas","descriptive":"Inclui quebras de página da fonte impressa original"},"ruby-annotations":"Algumas anotações Ruby","sign-language":"Língua gestual","tactile-graphics":{"compact":"Inclui gráficos táteis","descriptive":"Inclui gráficos táteis que facilitam o acesso a elementos visuais para pessoas cegas"},"tactile-objects":"Objetos táteis 3D","text-to-speech-hinting":"Sugestões para leitura em voz alta","title":"Informação adicional de acessibilidade","ultra-high-contrast-between-text-and-background":"Contraste muito elevado entre texto e fundo","visible-page-numbering":"Numeração de páginas visível","without-background-sounds":"Sem sons de fundo"},"conformance":{"a":{"compact":"Cumpre as normas mínimas de acessibilidade","descriptive":"A publicação contém uma declaração de conformidade que indica que cumpre o padrão EPUB Accessibility e WCAG 2 nível A"},"aa":{"compact":"Cumpre as normas aceites de acessibilidade","descriptive":"A publicação contém uma declaração de conformidade que indica que cumpre o padrão EPUB Accessibility e WCAG 2 nível AA"},"aaa":{"compact":"Excede as normas aceites de acessibilidade","descriptive":"A publicação contém uma declaração de conformidade que indica que cumpre o padrão EPUB Accessibility e WCAG 2 nível AAA"},"certifier":"A publicação foi certificada por ","certifier-credentials":"As credenciais do certificador são ","details":{"certification-info":"A publicação foi certificada em ","certifier-report":"Para mais informações, consulte o relatório do certificador","claim":"Esta publicação declara conformidade com","epub-accessibility-1-0":"EPUB Accessibility 1.0","epub-accessibility-1-1":"EPUB Accessibility 1.1","level-a":"Nível A","level-aa":"Nível AA","level-aaa":"Nível AAA","wcag-2-0":{"compact":"WCAG 2.0","descriptive":"Diretrizes de Acessibilidade para Conteúdo Web (WCAG) 2.0"},"wcag-2-1":{"compact":"WCAG 2.1","descriptive":"Diretrizes de Acessibilidade para Conteúdo Web (WCAG) 2.1"},"wcag-2-2":{"compact":"WCAG 2.2","descriptive":"Diretrizes de Acessibilidade para Conteúdo Web (WCAG) 2.2"}},"details-title":"Detalhes de conformidade","no":"Sem informação disponível","title":"Conformidade","unknown-standard":"Não foi possível determinar a conformidade com as normas de acessibilidade aceites para esta publicação"},"hazards":{"flashing":{"compact":"Conteúdo intermitente","descriptive":"A publicação contém conteúdo intermitente que pode causar crises fotossensíveis"},"flashing-none":{"compact":"Sem perigos de intermitência","descriptive":"A publicação não contém conteúdo intermitente que possa causar crises fotossensíveis"},"flashing-unknown":{"compact":"Risco de intermitência desconhecido","descriptive":"Não foi possível determinar se existe conteúdo intermitente que possa causar crises fotossensíveis"},"motion":{"compact":"Simulação de movimento","descriptive":"A publicação contém simulações de movimento que podem causar enjoo"},"motion-none":{"compact":"Sem simulação de movimento","descriptive":"A publicação não contém simulações de movimento que possam causar enjoo"},"motion-unknown":{"compact":"Risco de movimento desconhecido","descriptive":"Não foi possível determinar se existem simulações de movimento que possam causar enjoo"},"no-metadata":"Sem informação disponível","none":{"compact":"Sem perigos","descriptive":"A publicação não contém perigos conhecidos"},"sound":{"compact":"Sons sensíveis","descriptive":"A publicação contém sons que podem causar sensibilidade auditiva"},"sound-none":{"compact":"Sem perigos sonoros","descriptive":"A publicação não contém sons que possam causar sensibilidade auditiva"},"sound-unknown":{"compact":"Risco sonoro desconhecido","descriptive":"Não foi possível determinar se a publicação contém sons que possam causar sensibilidade auditiva"},"title":"Perigos","unknown":"Presença de perigos não determinada"},"legal-considerations":{"exempt":{"compact":"Declara isenção de conformidade em algumas jurisdições","descriptive":"Esta publicação declara isenção de conformidade em algumas jurisdições"},"no-metadata":"Sem informação disponível","title":"Considerações legais"},"navigation":{"index":{"compact":"Índice","descriptive":"Índice com ligações para entradas referenciadas"},"no-metadata":"Sem informação disponível","page-navigation":{"compact":"Ir para página","descriptive":"Lista de páginas que permite aceder às páginas da versão impressa original"},"structural":{"compact":"Títulos e estrutura","descriptive":"Elementos como títulos, tabelas, etc., para navegação estruturada"},"title":"Navegação","toc":{"compact":"Índice","descriptive":"Índice de conteúdos com ligações para todos os capítulos do texto"}},"rich-content":{"accessible-chemistry-as-latex":{"compact":"Fórmulas químicas em LaTeX","descriptive":"Fórmulas químicas em formato acessível (LaTeX)"},"accessible-chemistry-as-mathml":{"compact":"Fórmulas químicas em MathML","descriptive":"Fórmulas químicas em formato acessível (MathML)"},"accessible-math-as-latex":{"compact":"Matemática em LaTeX","descriptive":"Fórmulas matemáticas em formato acessível (LaTeX)"},"accessible-math-described":"Descrição textual das fórmulas matemáticas","closed-captions":{"compact":"Vídeos com legendas ocultas","descriptive":"Os vídeos incluídos na publicação têm legendas ocultas"},"extended-descriptions":"Imagens complexas com descrições detalhadas","math-as-mathml":{"compact":"Matemática em MathML","descriptive":"Fórmulas matemáticas em formato acessível (MathML)"},"open-captions":{"compact":"Vídeos com legendas abertas","descriptive":"Os vídeos incluídos na publicação têm legendas abertas"},"title":"Conteúdo rico","transcript":"Transcrição fornecida","unknown":"Sem informação disponível"},"ways-of-reading":{"nonvisual-reading":{"alt-text":{"compact":"Contém texto alternativo","descriptive":"Inclui descrições alternativas de texto para imagens"},"no-metadata":"Sem informação sobre leitura não visual","none":{"compact":"Não legível em leitura em voz alta ou braille dinâmico","descriptive":"O conteúdo não é legível em voz alta ou através de braille dinâmico"},"not-fully":{"compact":"Parcialmente legível em leitura em voz alta ou braille dinâmico","descriptive":"Nem todo o conteúdo é legível em voz alta ou através de braille dinâmico"},"readable":{"compact":"Totalmente legível em leitura em voz alta ou braille dinâmico","descriptive":"Todo o conteúdo pode ser lido em voz alta ou através de braille dinâmico"}},"prerecorded-audio":{"complementary":{"compact":"Contém clipes de áudio pré-gravados","descriptive":"O conteúdo contém clipes de áudio pré-gravados incorporados"},"no-metadata":"Sem informação sobre áudio pré-gravado","only":{"compact":"Apenas áudio pré-gravado","descriptive":"A publicação é apenas áudio e não possui alternativa em texto"},"synchronized":{"compact":"Áudio pré-gravado sincronizado com texto","descriptive":"Todo o conteúdo está disponível como áudio pré-gravado sincronizado com texto"}},"title":"Formas de leitura","visual-adjustments":{"modifiable":{"compact":"Aspeto personalizável","descriptive":"O aspeto do texto e o layout da página podem ser modificados de acordo com as capacidades do sistema de leitura (tipo e tamanho de letra, espaçamento entre parágrafos, frases, palavras e letras, bem como a cor de fundo e do texto)"},"unknown":"Sem informação sobre personalização do aspeto","unmodifiable":{"compact":"Aspeto não ajustável","descriptive":"O texto e o layout da página não podem ser modificados, uma vez que a experiência de leitura é semelhante à versão impressa, mas os sistemas de leitura ainda podem oferecer opções de ampliação"}}}}},"altIdentifier_many":"identificadores alternativos","altIdentifier_one":"identificador alternativo","altIdentifier_other":"identificadores alternativos","artist_many":"artistas","artist_one":"artista","artist_other":"artistas","author_many":"autores","author_one":"autor","author_other":"autores","collection_many":"coleções","collection_one":"coleção","collection_other":"coleções","colorist_many":"coloristas","colorist_one":"colorista","colorist_other":"coloristas","contributor_many":"colaboradores","contributor_one":"colaborador","contributor_other":"colaboradores","description":"descrição","duration":"duração","editor_many":"editores","editor_one":"editor","editor_other":"editores","identifier_many":"identificadores","identifier_one":"identificador","identifier_other":"identificadores","illustrator_many":"ilustradores","illustrator_one":"ilustrador","illustrator_other":"ilustradores","imprint_many":"chancelas","imprint_one":"chancela","imprint_other":"chancelas","inker_many":"arte-finalistas","inker_one":"arte-finalista","inker_other":"arte-finalistas","language_many":"idiomas","language_one":"idioma","language_other":"idiomas","letterer_many":"letristas","letterer_one":"letrista","letterer_other":"letristas","modified":"data de modificação","narrator_many":"narradores","narrator_one":"narrador","narrator_other":"narradores","numberOfPages":"número de páginas","penciler_many":"desenhadores","penciler_one":"desenhador","penciler_other":"desenhadores","published":"data de publicação","publisher_many":"editoras","publisher_one":"editora","publisher_other":"editoras","series_many":"séries","series_one":"série","series_other":"séries","subject_many":"temas","subject_one":"tema","subject_other":"temas","subtitle":"subtítulo","title":"título","translator_many":"tradutores","translator_one":"tradutor","translator_other":"tradutores"}}`),qe={publication:Ke}})),Ye=r({default:()=>Ze,publication:()=>Xe}),Xe,Ze,Qe=n((()=>{Xe=JSON.parse(`{"format":{"audiobook":"Ljudbok","audiobookJSON":"Ljudbok (manifest)","cbz":"Serietidning (CBZ-arkiv)","divina":"Divina-publikation","divinaJSON":"Divina (manifest)","epub":"EPUB","lcpa":"LCP-skyddad ljudbok","lcpdf":"LCP-skyddad PDF","lcpl":"LCP-licensdokument","pdf":"PDF","rwp":"Readium webbpublikation","rwpm":"Readium webbpublikation (manifest)","zab":"Ljudbok (arkiv)","zip":"ZIP-arkiv"},"kind":{"audiobook_one":"ljudbok","audiobook_other":"ljudböcker","book_one":"bok","book_other":"böcker","comic_one":"serietidning","comic_other":"serietidningar","document_one":"dokument","document_other":"dokument"},"metadata":{"accessibility":{"display-guide":{"accessibility-summary":{"no-metadata":"Information saknas","publisher-contact":"För mer information om den här publikationens tillgänglighet, kontakta utgivaren: ","title":"Kompletterande information om tillgänglighet"},"additional-accessibility-information":{"aria":{"compact":"Innehåller ARIA-roller","descriptive":"Innehållet har försetts med ARIA-roller för att tydliggöra strukturen och underlätta navigering"},"audio-descriptions":"Syntolkning","braille":"Punktskrift","color-not-sole-means-of-conveying-information":"Betydelse uttrycks aldrig enbart med färg","dyslexia-readability":"Förbättrad läsbarhet för personer med dyslexi","full-ruby-annotations":"Fullständig ruby-annotering","high-contrast-between-foreground-and-background-audio":"Hög kontrast mellan förgrundsljud och bakgrundsljud","high-contrast-between-text-and-background":"Hög kontrast mellan text och bakgrund","large-print":"Storstil","page-breaks":{"compact":"Innehåller sidnummer","descriptive":"Innehåller sidnummer från tryckt förlaga"},"ruby-annotations":"Viss ruby-annotering","sign-language":"Teckenspråk","tactile-graphics":{"compact":"Innehåller taktila bilder","descriptive":"Taktila bilder har lagts till för att tillgängliggöra visuella element för personer med synnedsättning"},"tactile-objects":"Taktila 3D-objekt","text-to-speech-hinting":"Innehåller uttalsinstruktioner för talsyntes","title":"Ytterligare tillgänglighetsinformation","ultra-high-contrast-between-text-and-background":"Extra hög kontrast mellan text och bakgrund","visible-page-numbering":"Synlig sidnumrering","without-background-sounds":"Utan bakgrundsljud"},"conformance":{"a":{"compact":"Publikationen uppfyller tillgänglighetskrav på en grundläggande nivå","descriptive":"Publikationen anger att den uppfyller standarderna EPUB Accessibility och WCAG 2 nivå A"},"aa":{"compact":"Publikationen uppfyller tillgänglighetskrav på en vedertagen nivå","descriptive":"Publikationen anger att den uppfyller standarderna EPUB Accessibility och WCAG 2 nivå AA"},"aaa":{"compact":"Publikationen uppfyller tillgänglighetskrav utöver en vedertagen nivå","descriptive":"Publikationen anger att den uppfyller standarderna EPUB Accessibility och WCAG 2 nivå AAA"},"certifier":"Publikationen är certifierad av ","certifier-credentials":"Certifierarens märkning är ","details":{"certification-info":"Publikationen certifierades ","certifier-report":"Se certifieringsrapporten för mer information","claim":"Publikationen anger att den uppfyller kraven enligt","epub-accessibility-1-0":"EPUB Accessibility 1.0","epub-accessibility-1-1":"EPUB Accessibility 1.1","level-a":"nivå A","level-aa":"nivå AA","level-aaa":"nivå AAA","wcag-2-0":{"compact":"WCAG 2.0","descriptive":"Web Content Accessibility Guidelines (WCAG) 2.0"},"wcag-2-1":{"compact":"WCAG 2.1","descriptive":"Web Content Accessibility Guidelines (WCAG) 2.1"},"wcag-2-2":{"compact":"WCAG 2.2","descriptive":"Web Content Accessibility Guidelines (WCAG) 2.2"}},"details-title":"Detaljerad information om tillgänglighetskrav","no":"Information saknas","title":"Tillgänglighetskrav","unknown-standard":"Det går inte att avgöra om publikationen uppfyller vedertagna tillgänglighetskrav"},"hazards":{"flashing":{"compact":"Blinkande innehåll","descriptive":"Publikationen har blinkande innehåll som kan vara skadligt för ljuskänsliga personer"},"flashing-none":{"compact":"Inga risker med blinkande innehåll","descriptive":"Publikationen har inget blinkande innehåll som kan vara skadligt för ljuskänsliga personer"},"flashing-unknown":{"compact":"Inga kända risker med blinkande innehåll","descriptive":"Förekomst av blinkande innehåll som kan vara skadligt för ljuskänsliga personer är okänd"},"motion":{"compact":"Rörelsesimulering","descriptive":"Publikationen innehåller rörelsesimulering som skulle kunna orsaka illamående"},"motion-none":{"compact":"Inga risker med rörelsesimulering","descriptive":"Publikationen innehåller ingen rörelsesimulering som skulle kunna orsaka illamående"},"motion-unknown":{"compact":"Inga kända risker med rörelsesimulering","descriptive":"Förekomst av rörelsesimulering som skulle kunna orsaka illamående är okänd"},"no-metadata":"Information saknas","none":{"compact":"Inga risker","descriptive":"Publikationen innehåller inga risker"},"sound":{"compact":"Ljud","descriptive":"Publikationen innehåller ljud som kan orsaka obehag"},"sound-none":{"compact":"Inga ljudrelaterade risker","descriptive":"Publikationen innehåller inget ljud som kan orsaka obehag"},"sound-unknown":{"compact":"Inga kända ljudrelaterade risker","descriptive":"Förekomst av ljud som kan orsaka obehag är okänd"},"title":"Risker","unknown":"Förekomst av risker är okänd"},"legal-considerations":{"exempt":{"compact":"Åberopar ett undantag från vissa lagstadgade tillgänglighetskrav","descriptive":"Publikationen åberopar ett undantag från vissa lagstadgade tillgänglighetskrav"},"no-metadata":"Information saknas","title":"Juridiska aspekter"},"navigation":{"index":{"compact":"Register","descriptive":"Register med länkar till innehållet"},"no-metadata":"Information saknas","page-navigation":{"compact":"Gå till sida","descriptive":"Sidindelning för navigering enligt sidnummer i tryckt förlaga"},"structural":{"compact":"Rubriker","descriptive":"Navigerbara element såsom rubriker eller tabeller"},"title":"Navigering","toc":{"compact":"Innehållsförteckning","descriptive":"Innehållsförteckning med länkar till alla kapitel"}},"rich-content":{"accessible-chemistry-as-latex":{"compact":"Kemiska formler i LaTeX","descriptive":"Kemiska formler i tillgängligt format (LaTeX)"},"accessible-chemistry-as-mathml":{"compact":"Kemiska formler i MathML","descriptive":"Kemiska formler i tillgängligt format (MathML)"},"accessible-math-as-latex":{"compact":"Matematik som LaTeX","descriptive":"Matematiska formler i tillgängligt format (LaTeX)"},"accessible-math-described":"Innehåller textbeskrivningar av matematik","closed-captions":{"compact":"Videoklipp har undertext som kan sättas på/stängas av","descriptive":"Videoklipp som ingår i publikationen har undertext som kan sättas på och stängas av (stängda undertexter)"},"extended-descriptions":"Informationsrika bilder har utökade bildbeskrivningar","math-as-mathml":{"compact":"Matematik som MathML","descriptive":"Matematiska formler i tillgängligt format (MathML)"},"open-captions":{"compact":"Videoklipp har undertext som inte kan stängas av","descriptive":"Videoklipp som ingår i publikationen har undertext som inte kan stängas av (öppna undertexter)"},"title":"Berikat innehåll","transcript":"Innehåller transkriptioner","unknown":"Information saknas"},"ways-of-reading":{"nonvisual-reading":{"alt-text":{"compact":"Har textalternativ (alt-texter)","descriptive":"Har textalternativ (alt-texter) till bilder"},"no-metadata":"Information om icke-visuell läsbarhet saknas","none":{"compact":"Kan inte läsas med uppläsningsfunktion eller punktskriftsskärm","descriptive":"Innehållet går inte att läsa med uppläsningsfunktion eller punktskriftsskärm"},"not-fully":{"compact":"Inte läsbart i sin helhet med uppläsningsfunktion eller punktskriftsskärm","descriptive":"Allt innehåll går inte att läsa med uppläsningsfunktion eller punktskriftsskärm"},"readable":{"compact":"Kan läsas med uppläsningsfunktion eller punktskriftsskärm","descriptive":"Hela innehållet går att läsa med uppläsningsfunktion eller punktskriftsskärm"}},"prerecorded-audio":{"complementary":{"compact":"Förinspelade ljudklipp","descriptive":"Innehåller förinspelade ljudklipp"},"no-metadata":"Information om förinspelat ljud saknas","only":{"compact":"Endast förinspelat ljud","descriptive":"Bok med ljud utan textalternativ"},"synchronized":{"compact":"Förinspelat ljud synkroniserat med texten","descriptive":"Hela innehållet finns tillgängligt som förinspelat ljud synkroniserat med texten"}},"title":"Olika sätt att läsa","visual-adjustments":{"modifiable":{"compact":"Utseendet kan justeras","descriptive":"Det går att justera text och layout i den utsträckning som läsprogrammet tillåter, till exempel typsnitt, storlek på text, avstånd mellan rader och stycken samt färg på text och bakgrund"},"unknown":"Information om möjlighet att justera utseende saknas","unmodifiable":{"compact":"Utseendet kan inte justeras","descriptive":"Text- och sidlayout kan inte justeras eftersom presentationen liknar en tryckt version, men läsprogram kan ha funktioner för att zooma in"}}}}},"altIdentifier_one":"alternativ identifikator","altIdentifier_other":"alternativa identifikatorer","artist_one":"konstnär","artist_other":"konstnärer","author_one":"författare","author_other":"författare","collection_one":"samling","collection_other":"samlingar","colorist_one":"färgläggare","colorist_other":"färgläggare","contributor_one":"medverkande","contributor_other":"medverkande","description":"beskrivning","duration":"speltid","editor_one":"redaktör","editor_other":"redaktörer","identifier_one":"identifikator","identifier_other":"identifikatorer","illustrator_one":"illustratör","illustrator_other":"illustratörer","imprint_one":"imprint","imprint_other":"imprints","inker_one":"tuschare","inker_other":"tuschare","language_one":"språk","language_other":"språk","letterer_one":"textare","letterer_other":"textare","modified":"ändringsdatum","narrator_one":"berättare","narrator_other":"berättare","numberOfPages":"sidantal","penciler_one":"skissare","penciler_other":"skissare","published":"utgivningsdatum","publisher_one":"utgivare","publisher_other":"utgivare","series_one":"serie","series_other":"serier","subject_one":"ämne","subject_other":"ämnen","subtitle":"undertitel","title":"titel","translator_one":"översättare","translator_other":"översättare"}}`),Ze={publication:Xe}})),$e={ar:()=>T(()=>Promise.resolve().then(()=>(fe(),le)),[]),da:()=>T(()=>Promise.resolve().then(()=>(ge(),pe)),[]),el:()=>T(()=>Promise.resolve().then(()=>(be(),_e)),[]),es:()=>T(()=>Promise.resolve().then(()=>(we(),xe)),[]),et:()=>T(()=>Promise.resolve().then(()=>(Oe(),Te)),[]),fi:()=>T(()=>Promise.resolve().then(()=>(Me(),ke)),[]),fr:()=>T(()=>Promise.resolve().then(()=>(Ie(),Ne)),[]),it:()=>T(()=>Promise.resolve().then(()=>(Be(),Le)),[]),pl:()=>T(()=>Promise.resolve().then(()=>(We(),Ve)),[]),pt_PT:()=>T(()=>Promise.resolve().then(()=>(Je(),Ge)),[]),sv:()=>T(()=>Promise.resolve().then(()=>(Qe(),Ye)),[])},et=ce?.publication?.metadata?.accessibility?.[`display-guide`]||{},E=class e{constructor(){this.currentLocaleCode=`en`,this.locale=et,this.loadedLocales={},this.loadedLocales.en=et}static getInstance(){return e.instance||=new e,e.instance}async loadLocale(e){if(!se.includes(e))return console.warn(`Locale '${e}' is not enabled`),!1;if(e in this.loadedLocales)return!0;try{if(!(e in $e))return console.warn(`Locale file not found for: ${e}`),!1;let t=(await $e[e]()).default?.publication?.metadata?.accessibility?.[`display-guide`];return t?(this.loadedLocales[e]=t,!0):(console.warn(`No accessibility strings found in locale ${e}`),!1)}catch(t){return console.warn(`Failed to load locale ${e}:`,t),!1}}registerLocale(e,t){if(!e||typeof e!=`string`)throw Error(`Locale code must be a non-empty string`);this.loadedLocales[e]=t}async setLocale(e){return e in this.loadedLocales||await this.loadLocale(e),e in this.loadedLocales?(this.locale=this.loadedLocales[e],this.currentLocaleCode=e,!0):(console.warn(`Locale '${e}' is not available`),!1)}getCurrentLocale(){return this.currentLocaleCode}getAvailableLocales(){return se}getNestedValue(e,t){let n=t.split(`.`),r=e;for(let e of n){if(r==null)return;r=r[e]}return r}getString(e){let t=this.getNestedValue(this.locale,e);return t===void 0&&this.currentLocaleCode!==`en`&&(t=this.getNestedValue(this.loadedLocales.en,e)),t===void 0?(console.warn(`Missing localization for key: ${e}`),{compact:``,descriptive:``}):typeof t==`string`?{compact:t,descriptive:t}:t}}.getInstance(),D=(e=>(e.reflowable=`reflowable`,e.fixed=`fixed`,e.scrolled=`scrolled`,e))(D||{}),tt=(e=>(e.Unknown=`unknown`,e.Modifiable=`modifiable`,e.Unmodifiable=`unmodifiable`,e))(tt||{}),nt=(e=>(e.NoMetadata=`noMetadata`,e.Readable=`readable`,e.NotFully=`notFully`,e.Unreadable=`unreadable`,e))(nt||{}),rt=(e=>(e.NoMetadata=`noMetadata`,e.Synchronized=`synchronized`,e.AudioOnly=`audioOnly`,e.AudioComplementary=`audioComplementary`,e))(rt||{}),it=class e{constructor(e=`unknown`,t=`noMetadata`,n=!1,r=`noMetadata`){this.id=`ways-of-reading.title`,this.visualAdjustments=e,this.nonvisualReading=t,this.nonvisualReadingAltText=n,this.prerecordedAudio=r,this.shouldDisplay=!0;let i=E.getString(this.id);this.title=i.compact,this.statements=[];let a=e===`modifiable`?`ways-of-reading.visual-adjustments.modifiable`:e===`unmodifiable`?`ways-of-reading.visual-adjustments.unmodifiable`:`ways-of-reading.visual-adjustments.unknown`,o=E.getString(a);this.statements.push({id:a,compactString:o.compact,descriptiveString:o.descriptive});let s=``;t===`readable`?s=`ways-of-reading.nonvisual-reading.readable`:t===`notFully`?s=`ways-of-reading.nonvisual-reading.not-fully`:t===`unreadable`?s=`ways-of-reading.nonvisual-reading.none`:t===`noMetadata`&&(s=`ways-of-reading.nonvisual-reading.no-metadata`);let c=E.getString(s);if(this.statements.push({id:s,compactString:c.compact,descriptiveString:c.descriptive}),n){let e=E.getString(`ways-of-reading.nonvisual-reading.alt-text`);this.statements.push({id:`ways-of-reading.nonvisual-reading.alt-text`,compactString:e.compact,descriptiveString:e.descriptive})}let l=``;r===`synchronized`?l=`ways-of-reading.prerecorded-audio.synchronized`:r===`audioOnly`?l=`ways-of-reading.prerecorded-audio.only`:r===`audioComplementary`?l=`ways-of-reading.prerecorded-audio.complementary`:r===`noMetadata`&&(l=`ways-of-reading.prerecorded-audio.no-metadata`);let u=E.getString(l);this.statements.push({id:l,compactString:u.compact,descriptiveString:u.descriptive})}static fromPublication(t){let n=t.metadata.accessibility??new h,r=n.feature??[],i=t.metadata.layout===D.fixed,a=r.some(e=>e.value===x.DISPLAY_TRANSFORMABILITY.value)?`modifiable`:i?`unmodifiable`:`unknown`,o=n.accessMode??[],s=n.accessModeSufficient??[],c=o.length>0&&o.every(e=>e.value===v.TEXTUAL.value)||s.some(e=>{let t=e.value;return Array.isArray(t)?t.every(e=>e===v.TEXTUAL.value):t===v.TEXTUAL.value}),l=o.some(e=>e.value===v.TEXTUAL.value)||s.some(e=>{let t=e.value;return Array.isArray(t)?t.some(e=>e===v.TEXTUAL.value):t===v.TEXTUAL.value}),u=(o.length!==0||s.length!==0)&&!o.some(e=>e.value===v.TEXTUAL.value)&&!s.some(e=>{let t=e.value;return Array.isArray(t)?t.some(e=>e===v.TEXTUAL.value):t===v.TEXTUAL.value}),d=r.some(e=>[x.LONG_DESCRIPTION.value,x.ALTERNATIVE_TEXT.value,x.DESCRIBED_MATH.value,x.TRANSCRIPT.value].includes(e.value)),f=c?`readable`:l||d?`notFully`:u?`unreadable`:`noMetadata`,p=d,m=r.some(e=>e.value===x.SYNCHRONIZED_AUDIO_TEXT.value)?`synchronized`:s.some(e=>{let t=e.value;return Array.isArray(t)?t.some(e=>e===v.AUDITORY.value):t===v.AUDITORY.value})?`audioOnly`:o.some(e=>e.value===v.AUDITORY.value)?`audioComplementary`:`noMetadata`;return new e(a,f,p,m)}},at=class e{constructor(e=!1,t=!1,n=!1,r=!1){this.id=`navigation.title`,this.tableOfContents=e,this.index=t,this.headings=n,this.page=r,this.noMetadata=!e&&!t&&!n&&!r;let i=E.getString(this.id);if(this.title=i.compact,this.shouldDisplay=!this.noMetadata,this.statements=[],e){let e=E.getString(`navigation.toc`);this.statements.push({id:`navigation.toc`,compactString:e.compact,descriptiveString:e.descriptive})}if(t){let e=E.getString(`navigation.index`);this.statements.push({id:`navigation.index`,compactString:e.compact,descriptiveString:e.descriptive})}if(n){let e=E.getString(`navigation.structural`);this.statements.push({id:`navigation.structural`,compactString:e.compact,descriptiveString:e.descriptive})}if(r){let e=E.getString(`navigation.page-navigation`);this.statements.push({id:`navigation.page-navigation`,compactString:e.compact,descriptiveString:e.descriptive})}if(this.statements.length===0){let e=E.getString(`navigation.no-metadata`);this.statements.push({id:`navigation.no-metadata`,compactString:e.compact,descriptiveString:e.descriptive})}}static fromPublication(t){let n=(t.metadata.accessibility??new h).feature??[];return new e(n.some(e=>e.value===x.TABLE_OF_CONTENTS.value),n.some(e=>e.value===x.INDEX.value),n.some(e=>e.value===x.STRUCTURAL_NAVIGATION.value),n.some(e=>e.value===x.PAGE_NAVIGATION.value))}},ot=(e=>(e.Math=`math`,e.Chemistry=`chemistry`,e.Music=`music`,e.Diagram=`diagram`,e.Chart=`chart`,e.Graph=`graph`,e.Table=`table`,e.Image=`image`,e))(ot||{}),st=class e{constructor(e=!1,t=!1,n=!1,r=!1,i=!1,a=!1,o=!1,s=!1,c=!1){this.id=`rich-content.title`,this.extendedAltTextDescriptions=e,this.mathFormula=t,this.mathFormulaAsMathML=n,this.mathFormulaAsLaTeX=r,this.chemicalFormulaAsMathML=i,this.chemicalFormulaAsLaTeX=a,this.closedCaptions=o,this.openCaptions=s,this.transcript=c,this.noMetadata=!e&&!t&&!n&&!r&&!i&&!a&&!o&&!s&&!c,this.shouldDisplay=!this.noMetadata;let l=E.getString(this.id);if(this.title=l.compact,this.statements=[],e){let e=E.getString(`rich-content.extended-descriptions`);this.statements.push({id:`rich-content.extended-descriptions`,compactString:e.compact,descriptiveString:e.descriptive})}if(t){let e=E.getString(`rich-content.accessible-math-described`);this.statements.push({id:`rich-content.accessible-math-described`,compactString:e.compact,descriptiveString:e.descriptive})}if(n){let e=E.getString(`rich-content.math-as-mathml`);this.statements.push({id:`rich-content.math-as-mathml`,compactString:e.compact,descriptiveString:e.descriptive})}if(r){let e=E.getString(`rich-content.accessible-math-as-latex`);this.statements.push({id:`rich-content.accessible-math-as-latex`,compactString:e.compact,descriptiveString:e.descriptive})}if(i){let e=E.getString(`rich-content.accessible-chemistry-as-mathml`);this.statements.push({id:`rich-content.accessible-chemistry-as-mathml`,compactString:e.compact,descriptiveString:e.descriptive})}if(a){let e=E.getString(`rich-content.accessible-chemistry-as-latex`);this.statements.push({id:`rich-content.accessible-chemistry-as-latex`,compactString:e.compact,descriptiveString:e.descriptive})}if(o){let e=E.getString(`rich-content.closed-captions`);this.statements.push({id:`rich-content.closed-captions`,compactString:e.compact,descriptiveString:e.descriptive})}if(s){let e=E.getString(`rich-content.open-captions`);this.statements.push({id:`rich-content.open-captions`,compactString:e.compact,descriptiveString:e.descriptive})}if(c){let e=E.getString(`rich-content.transcript`);this.statements.push({id:`rich-content.transcript`,compactString:e.compact,descriptiveString:e.descriptive})}if(this.statements.length===0){let e=E.getString(`rich-content.unknown`);this.statements.push({id:`rich-content.unknown`,compactString:e.compact,descriptiveString:e.descriptive})}}static fromPublication(t){let n=(t.metadata.accessibility??new h).feature??[];return new e(n.some(e=>e.value===x.LONG_DESCRIPTION.value),n.some(e=>e.value===x.DESCRIBED_MATH.value),n.some(e=>e.value===x.MATH_ML.value),n.some(e=>e.value===x.LATEX.value),n.some(e=>e.value===x.MATH_ML_CHEMISTRY.value),n.some(e=>e.value===x.LATEX_CHEMISTRY.value),n.some(e=>e.value===x.CLOSED_CAPTIONS.value),n.some(e=>e.value===x.OPEN_CAPTIONS.value),n.some(e=>e.value===x.TRANSCRIPT.value))}},ct=class e{constructor(e=!1,t=!1,n=!1,r=!1,i=!1,a=!1,o=!1,s=!1,c=!1,l=!1,u=!1,d=!1,f=!1){this.id=`additional-accessibility-information.title`,this.pageBreakMarkers=e,this.aria=t,this.audioDescriptions=n,this.braille=r,this.rubyAnnotations=i,this.fullRubyAnnotations=a,this.highAudioContrast=o,this.highDisplayContrast=s,this.largePrint=c,this.signLanguage=l,this.tactileGraphics=u,this.tactileObjects=d,this.textToSpeechHinting=f,this.noMetadata=!e&&!t&&!n&&!r&&!i&&!a&&!o&&!s&&!c&&!l&&!u&&!d&&!f,this.shouldDisplay=!this.noMetadata;let p=E.getString(this.id);if(this.title=p.compact,this.statements=[],e){let e=E.getString(`additional-accessibility-information.page-breaks`);this.statements.push({id:`additional-accessibility-information.page-breaks`,compactString:e.compact,descriptiveString:e.descriptive})}if(t){let e=E.getString(`additional-accessibility-information.aria`);this.statements.push({id:`additional-accessibility-information.aria`,compactString:e.compact,descriptiveString:e.descriptive})}if(n){let e=E.getString(`additional-accessibility-information.audio-descriptions`);this.statements.push({id:`additional-accessibility-information.audio-descriptions`,compactString:e.compact,descriptiveString:e.descriptive})}if(r){let e=E.getString(`additional-accessibility-information.braille`);this.statements.push({id:`additional-accessibility-information.braille`,compactString:e.compact,descriptiveString:e.descriptive})}if(i){let e=E.getString(`additional-accessibility-information.ruby-annotations`);this.statements.push({id:`additional-accessibility-information.ruby-annotations`,compactString:e.compact,descriptiveString:e.descriptive})}if(a){let e=E.getString(`additional-accessibility-information.full-ruby-annotations`);this.statements.push({id:`additional-accessibility-information.full-ruby-annotations`,compactString:e.compact,descriptiveString:e.descriptive})}if(o){let e=E.getString(`additional-accessibility-information.high-contrast-between-foreground-and-background-audio`);this.statements.push({id:`additional-accessibility-information.high-contrast-between-foreground-and-background-audio`,compactString:e.compact,descriptiveString:e.descriptive})}if(s){let e=E.getString(`additional-accessibility-information.high-contrast-between-text-and-background`);this.statements.push({id:`additional-accessibility-information.high-contrast-between-text-and-background`,compactString:e.compact,descriptiveString:e.descriptive})}if(c){let e=E.getString(`additional-accessibility-information.large-print`);this.statements.push({id:`additional-accessibility-information.large-print`,compactString:e.compact,descriptiveString:e.descriptive})}if(l){let e=E.getString(`additional-accessibility-information.sign-language`);this.statements.push({id:`additional-accessibility-information.sign-language`,compactString:e.compact,descriptiveString:e.descriptive})}if(u){let e=E.getString(`additional-accessibility-information.tactile-graphics`);this.statements.push({id:`additional-accessibility-information.tactile-graphics`,compactString:e.compact,descriptiveString:e.descriptive})}if(d){let e=E.getString(`additional-accessibility-information.tactile-objects`);this.statements.push({id:`additional-accessibility-information.tactile-objects`,compactString:e.compact,descriptiveString:e.descriptive})}if(f){let e=E.getString(`additional-accessibility-information.text-to-speech-hinting`);this.statements.push({id:`additional-accessibility-information.text-to-speech-hinting`,compactString:e.compact,descriptiveString:e.descriptive})}}static fromPublication(t){let n=(t.metadata.accessibility??new h).feature??[];return new e(n.some(e=>e.value===x.PAGE_BREAK_MARKERS.value||e.value===x.PRINT_PAGE_NUMBERS.value),n.some(e=>e.value===x.ARIA.value),n.some(e=>e.value===x.AUDIO_DESCRIPTION.value),n.some(e=>e.value===x.BRAILLE.value),n.some(e=>e.value===x.RUBY_ANNOTATIONS.value),n.some(e=>e.value===x.FULL_RUBY_ANNOTATIONS.value),n.some(e=>e.value===x.HIGH_CONTRAST_AUDIO.value),n.some(e=>e.value===x.HIGH_CONTRAST_DISPLAY.value),n.some(e=>e.value===x.LARGE_PRINT.value),n.some(e=>e.value===x.SIGN_LANGUAGE.value),n.some(e=>e.value===x.TACTILE_GRAPHIC.value),n.some(e=>e.value===x.TACTILE_OBJECT.value),n.some(e=>e.value===x.TTS_MARKUP.value))}},lt=(e=>(e.yes=`yes`,e.no=`no`,e.unknown=`unknown`,e.noMetadata=`noMetadata`,e))(lt||{}),ut=class e{constructor(e=`unknown`,t=`unknown`,n=`unknown`){this.id=`hazards.title`,this.flashing=e,this.motion=t,this.sound=n;let r=E.getString(this.id);if(this.title=r.compact,this.noMetadata=e===`noMetadata`&&t===`noMetadata`&&n===`noMetadata`,this.noHazards=e===`no`&&t===`no`&&n===`no`,this.unknown=e===`unknown`&&t===`unknown`&&n===`unknown`,this.shouldDisplay=!this.noMetadata,this.statements=[],this.noHazards){let e=E.getString(`hazards.none`);this.statements.push({id:`hazards.none`,compactString:e.compact,descriptiveString:e.descriptive})}else if(this.unknown){let e=E.getString(`hazards.unknown`);this.statements.push({id:`hazards.unknown`,compactString:e.compact,descriptiveString:e.descriptive})}else if(this.noMetadata){let e=E.getString(`hazards.no-metadata`);this.statements.push({id:`hazards.no-metadata`,compactString:e.compact,descriptiveString:e.descriptive})}else{if(e===`yes`){let e=E.getString(`hazards.flashing`);this.statements.push({id:`hazards.flashing`,compactString:e.compact,descriptiveString:e.descriptive})}else if(e===`unknown`){let e=E.getString(`hazards.flashing-unknown`);this.statements.push({id:`hazards.flashing-unknown`,compactString:e.compact,descriptiveString:e.descriptive})}else if(e===`no`){let e=E.getString(`hazards.flashing-none`);this.statements.push({id:`hazards.flashing-none`,compactString:e.compact,descriptiveString:e.descriptive})}if(t===`yes`){let e=E.getString(`hazards.motion`);this.statements.push({id:`hazards.motion`,compactString:e.compact,descriptiveString:e.descriptive})}else if(t===`unknown`){let e=E.getString(`hazards.motion-unknown`);this.statements.push({id:`hazards.motion-unknown`,compactString:e.compact,descriptiveString:e.descriptive})}else if(t===`no`){let e=E.getString(`hazards.motion-none`);this.statements.push({id:`hazards.motion-none`,compactString:e.compact,descriptiveString:e.descriptive})}if(n===`yes`){let e=E.getString(`hazards.sound`);this.statements.push({id:`hazards.sound`,compactString:e.compact,descriptiveString:e.descriptive})}else if(n===`unknown`){let e=E.getString(`hazards.sound-unknown`);this.statements.push({id:`hazards.sound-unknown`,compactString:e.compact,descriptiveString:e.descriptive})}else if(n===`no`){let e=E.getString(`hazards.sound-none`);this.statements.push({id:`hazards.sound-none`,compactString:e.compact,descriptiveString:e.descriptive})}}}static fromPublication(t){let n=t.metadata.accessibility?.hazard??[],r;r=n.some(e=>e.value===C.NONE.value)?`no`:n.some(e=>e.value===C.UNKNOWN.value)?`unknown`:`noMetadata`;let i;i=n.some(e=>e.value===C.FLASHING.value)?`yes`:n.some(e=>e.value===C.NO_FLASHING_HAZARD.value)?`no`:n.some(e=>e.value===C.UNKNOWN_FLASHING_HAZARD.value)?`unknown`:r;let a;a=n.some(e=>e.value===C.MOTION_SIMULATION.value)?`yes`:n.some(e=>e.value===C.NO_MOTION_SIMULATION_HAZARD.value)?`no`:n.some(e=>e.value===C.UNKNOWN_MOTION_SIMULATION_HAZARD.value)?`unknown`:r;let o;return o=n.some(e=>e.value===C.SOUND.value)?`yes`:n.some(e=>e.value===C.NO_SOUND_HAZARD.value)?`no`:n.some(e=>e.value===C.UNKNOWN_SOUND_HAZARD.value)?`unknown`:r,new e(i,a,o)}},dt=class e{constructor(e=[]){this.id=`conformance.title`,this.profiles=e,this.shouldDisplay=!0;let t=E.getString(this.id);if(this.title=t.compact,this.statements=[],e.length===0){let e=E.getString(`conformance.no`);this.statements.push({id:`conformance.no`,compactString:e.compact,descriptiveString:e.descriptive})}else if(e.some(e=>e.isWCAGLevelAAA)){let e=E.getString(`conformance.aaa`);this.statements.push({id:`conformance.aaa`,compactString:e.compact,descriptiveString:e.descriptive})}else if(e.some(e=>e.isWCAGLevelAA)){let e=E.getString(`conformance.aa`);this.statements.push({id:`conformance.aa`,compactString:e.compact,descriptiveString:e.descriptive})}else if(e.some(e=>e.isWCAGLevelA)){let e=E.getString(`conformance.a`);this.statements.push({id:`conformance.a`,compactString:e.compact,descriptiveString:e.descriptive})}else{let e=E.getString(`conformance.unknown-standard`);this.statements.push({id:`conformance.unknown-standard`,compactString:e.compact,descriptiveString:e.descriptive})}}static fromPublication(t){let n=t.metadata.accessibility?.conformsTo??[];return new e(n)}},ft=class e{constructor(e=!1){this.id=`legal-considerations.title`,this.exemption=e,this.shouldDisplay=this.exemption;let t=E.getString(this.id);if(this.title=t.compact,this.statements=[],e){let e=E.getString(`legal-considerations.exempt`);this.statements.push({id:`legal-considerations.exempt`,compactString:e.compact,descriptiveString:e.descriptive})}else{let e=E.getString(`legal-considerations.no-metadata`);this.statements.push({id:`legal-considerations.no-metadata`,compactString:e.compact,descriptiveString:e.descriptive})}}static fromPublication(t){let n=(t.metadata.accessibility?.exemption??[]).length>0;return new e(n)}},pt=class e{constructor(e){this.id=`accessibility-summary.title`,this.shouldDisplay=!0;let t=E.getString(this.id);this.title=t.compact;let n=e.metadata.accessibility?.summary;if(this.statements=[],this.shouldDisplay&&n)this.statements.push({id:`accessibility-summary.summary`,compactString:n,descriptiveString:n});else{let e=E.getString(`accessibility-summary.no-metadata`);this.statements.push({id:`accessibility-summary.no-metadata`,compactString:e.compact,descriptiveString:e.descriptive})}}static fromPublication(t){return new e(t)}},mt=class{constructor(e){this.waysOfReading=it.fromPublication(e),this.navigation=at.fromPublication(e),this.richContent=st.fromPublication(e),this.additionalInformation=ct.fromPublication(e),this.hazards=ut.fromPublication(e),this.conformance=dt.fromPublication(e),this.legal=ft.fromPublication(e),this.accessibilitySummary=pt.fromPublication(e),this.fields=[this.waysOfReading,this.navigation,this.richContent,this.additionalInformation,this.hazards,this.conformance,this.legal,this.accessibilitySummary]}},ht=class e{constructor(e){this.algorithm=e.algorithm,this.compression=e.compression,this.originalLength=e.originalLength,this.profile=e.profile,this.scheme=e.scheme}static deserialize(t){if(t&&t.algorithm)return new e({algorithm:t.algorithm,compression:t.compression,originalLength:t.originalLength,profile:t.profile,scheme:t.scheme})}serialize(){let e={algorithm:this.algorithm};return this.compression!==void 0&&(e.compression=this.compression),this.originalLength!==void 0&&(e.originalLength=this.originalLength),this.profile!==void 0&&(e.profile=this.profile),this.scheme!==void 0&&(e.scheme=this.scheme),e}};function gt(e){return ht.deserialize(e.otherProperties.encrypted)}var _t=class e{constructor(e){this.activeClass=e.activeClass,this.playbackActiveClass=e.playbackActiveClass}static deserialize(t){if(t)return new e({activeClass:t.activeClass,playbackActiveClass:t.playbackActiveClass})}serialize(){let e={};return this.activeClass&&(e.activeClass=this.activeClass),this.playbackActiveClass&&(e.playbackActiveClass=this.playbackActiveClass),e}};function vt(e){let t=e.otherMetadata?.mediaOverlay;if(t)return _t.deserialize(t)}function yt(e){return new Set(e.otherProperties.contains||[])}function bt(e){return e.linksWithRole(`pageList`)}function xt(e){return e.linksWithRole(`landmarks`)}function St(e){return e.linksWithRole(`loa`)}function Ct(e){return e.linksWithRole(`loi`)}function wt(e){return e.linksWithRole(`lot`)}function Tt(e){return e.linksWithRole(`lov`)}var Et=class e{constructor(e){this.cssSelector=e.cssSelector,this.textNodeIndex=e.textNodeIndex,this.charOffset=e.charOffset}static deserialize(t){if(!(t&&t.cssSelector))return;let n=p(t.textNodeIndex);if(n===void 0)return;let r=p(t.charOffset);return r===void 0&&(r=p(t.offset)),new e({cssSelector:t.cssSelector,textNodeIndex:n,charOffset:r})}serialize(){let e={cssSelector:this.cssSelector,textNodeIndex:this.textNodeIndex};return this.charOffset!==void 0&&(e.charOffset=this.charOffset),e}},Dt=class e{constructor(e){this.start=e.start,this.end=e.end}static deserialize(t){if(!t)return;let n=Et.deserialize(t.start);if(n)return new e({start:n,end:Et.deserialize(t.end)})}serialize(){let e={start:this.start.serialize()};return this.end&&(e.end=this.end.serialize()),e}};function Ot(e){let t=e.split(`,`)[0].trim(),n=(t.toLowerCase().startsWith(`npt:`)?t.slice(4):t).split(`:`);if(n.length===1){let e=parseFloat(n[0]);return isNaN(e)?void 0:e}if(n.length===2){let e=parseInt(n[0],10),t=parseFloat(n[1]);return isNaN(e)||isNaN(t)?void 0:e*60+t}if(n.length===3){let e=parseInt(n[0],10),t=parseInt(n[1],10),r=parseFloat(n[2]);return isNaN(e)||isNaN(t)||isNaN(r)?void 0:e*3600+t*60+r}}function kt(e){let t=Ot(e);return t!==void 0&&t===0}function At(e){let t=Math.floor(e),n=Math.floor(t/3600),r=Math.floor(t%3600/60),i=t%60,a=String(r).padStart(2,`0`),o=String(i).padStart(2,`0`);return n>0?`${n}:${a}:${o}`:`${r}:${o}`}var jt=`:~:text=`;function Mt(e){if(!e)return;let t=e.indexOf(jt);if(t===-1)return;let n=e.slice(t+8).split(`&`)[0];if(n)try{let e=n.split(`,`),t={textStart:``};return e.length>1&&e[0].endsWith(`-`)&&(t.prefix=decodeURIComponent(e[0].slice(0,-1)),e=e.slice(1)),e.length>1&&e[e.length-1].startsWith(`-`)&&(t.suffix=decodeURIComponent(e[e.length-1].slice(1)),e=e.slice(0,-1)),e.length===0||e[0]===``?void 0:(t.textStart=decodeURIComponent(e[0]),e.length>1&&(t.textEnd=decodeURIComponent(e[1])),t)}catch{return}}function Nt(e){return e.otherLocations?.get(`cssSelector`)}function Pt(e){return e.otherLocations?.get(`partialCfi`)}function Ft(e){return Dt.deserialize(e.otherLocations?.get(`domRange`))}function It(e){return e.fragments?.map(e=>Mt(e)).find(e=>e)}function Lt(e){return new Map(e.fragments?.map(e=>e.startsWith(`#`)?e.slice(1):e).join(`&`).split(`&`).filter(e=>!e.startsWith(`#`)).map(e=>e.split(`=`)).filter(e=>e.length===2).map(e=>[e[0].trim().toLowerCase(),e[1].trim()]))}function Rt(e){if(!e.fragments?.length)return;let t=e.fragments.find(e=>e.length&&!e.includes(`=`));if(!t){let n=Lt(e);n.has(`id`)?t=n.get(`id`):n.has(`name`)&&(t=n.get(`name`))}return t?.startsWith(`#`)?t.slice(1):t}function zt(e){let t=parseInt(Lt(e).get(`page`));if(!isNaN(t)&&t>=0)return t}function Bt(e){let t=Lt(e).get(`t`);if(t)return Ot(t)}function Vt(e){let t=Lt(e);if(!t.has(`xywh`))return;let n=t.get(`xywh`),r=`pixel`,i=n,a=n.toLowerCase();a.startsWith(`pixel:`)?i=n.slice(6):a.startsWith(`percent:`)&&(r=`percent`,i=n.slice(8));let o=r===`percent`?parseFloat:e=>parseInt(e,10),s=i.split(`,`).map(o);if(s.length!==4||s.some(isNaN))return;let[c,l,u,d]=s;return{unit:r,x:c,y:l,width:u,height:d}}var Ht=class e{constructor(e){let t,n,r=e.mediaType.replace(/\s/g,``).split(`;`),i=r[0].split(`/`);if(i.length===2){if(t=i[0].toLowerCase().trim(),n=i[1].toLowerCase().trim(),t.length===0||n.length===0)throw Error(`Invalid media type`)}else throw Error(`Invalid media type`);let a={};for(let e=1;e<r.length;e++){let t=r[e].split(`=`);if(t.length===2){let e=t[0].toLocaleLowerCase();a[e]=e===`charset`?t[1].toUpperCase():t[1]}}let o={},s=Object.keys(a);s.sort((e,t)=>e.localeCompare(t)),s.forEach(e=>o[e]=a[e]);let c=``;for(let e in o){let t=o[e];c+=`;${e}=${t}`}let l=`${t}/${n}${c}`,u=o.encoding;this.string=l,this.type=t,this.subtype=n,this.parameters=o,this.encoding=u,this.name=e.name,this.fileExtension=e.fileExtension}static parse(t){return new e(t)}get structuredSyntaxSuffix(){let e=this.subtype.split(`+`);return e.length>1?`+${e[e.length-1]}`:void 0}get essence(){return`${this.type}/${this.subtype}`}get charset(){return this.parameters.charset}contains(t){let n=typeof t==`string`?e.parse({mediaType:t}):t;if(this.type!==`*`&&this.type!==n.type||this.subtype!==`*`&&this.subtype!==n.subtype)return!1;let r=new Set(Object.entries(this.parameters).map(([e,t])=>`${e}=${t}`)),i=new Set(Object.entries(n.parameters).map(([e,t])=>`${e}=${t}`));for(let e of Array.from(r.values()))if(!i.has(e))return!1;return!0}matches(t){let n=typeof t==`string`?e.parse({mediaType:t}):t;return this.contains(n)||n.contains(this)}matchesAny(...e){for(let t of e)if(this.matches(t))return!0;return!1}equals(e){return this.string===e.string}get isZIP(){return this.matchesAny(e.ZIP,e.LCP_PROTECTED_AUDIOBOOK,e.LCP_PROTECTED_PDF)||this.structuredSyntaxSuffix===`+zip`}get isJSON(){return this.matchesAny(e.JSON)||this.structuredSyntaxSuffix===`+json`}get isOPDS(){return this.matchesAny(e.OPDS1,e.OPDS1_ENTRY,e.OPDS2,e.OPDS2_PUBLICATION,e.OPDS_AUTHENTICATION)||this.structuredSyntaxSuffix===`+json`}get isHTML(){return this.matchesAny(e.HTML,e.XHTML)}get isBitmap(){return this.matchesAny(e.AVIF,e.BMP,e.GIF,e.JPEG,e.PNG,e.TIFF,e.WEBP)}get isAudio(){return this.type===`audio`}get isVideo(){return this.type===`video`}get isRWPM(){return this.matchesAny(e.READIUM_AUDIOBOOK_MANIFEST,e.DIVINA_MANIFEST,e.READIUM_WEBPUB_MANIFEST)}get isPublication(){return this.matchesAny(e.READIUM_AUDIOBOOK,e.READIUM_AUDIOBOOK_MANIFEST,e.CBZ,e.DIVINA,e.DIVINA_MANIFEST,e.EPUB,e.LCP_PROTECTED_AUDIOBOOK,e.LCP_PROTECTED_PDF,e.LPF,e.PDF,e.W3C_WPUB_MANIFEST,e.READIUM_WEBPUB,e.READIUM_WEBPUB_MANIFEST,e.ZAB)}static get AAC(){return e.parse({mediaType:`audio/aac`,fileExtension:`aac`})}static get ACSM(){return e.parse({mediaType:`application/vnd.adobe.adept+xml`,name:`Adobe Content Server Message`,fileExtension:`acsm`})}static get AIFF(){return e.parse({mediaType:`audio/aiff`,fileExtension:`aiff`})}static get AVI(){return e.parse({mediaType:`video/x-msvideo`,fileExtension:`avi`})}static get AVIF(){return e.parse({mediaType:`image/avif`,fileExtension:`avif`})}static get BINARY(){return e.parse({mediaType:`application/octet-stream`})}static get BMP(){return e.parse({mediaType:`image/bmp`,fileExtension:`bmp`})}static get CBZ(){return e.parse({mediaType:`application/vnd.comicbook+zip`,name:`Comic Book Archive`,fileExtension:`cbz`})}static get CSS(){return e.parse({mediaType:`text/css`,fileExtension:`css`})}static get DIVINA(){return e.parse({mediaType:`application/divina+zip`,name:`Digital Visual Narratives`,fileExtension:`divina`})}static get DIVINA_MANIFEST(){return e.parse({mediaType:`application/divina+json`,name:`Digital Visual Narratives`,fileExtension:`json`})}static get EPUB(){return e.parse({mediaType:`application/epub+zip`,name:`EPUB`,fileExtension:`epub`})}static get GIF(){return e.parse({mediaType:`image/gif`,fileExtension:`gif`})}static get GZ(){return e.parse({mediaType:`application/gzip`,fileExtension:`gz`})}static get HTML(){return e.parse({mediaType:`text/html`,fileExtension:`html`})}static get JAVASCRIPT(){return e.parse({mediaType:`text/javascript`,fileExtension:`js`})}static get JPEG(){return e.parse({mediaType:`image/jpeg`,fileExtension:`jpeg`})}static get JSON(){return e.parse({mediaType:`application/json`})}static get LCP_LICENSE_DOCUMENT(){return e.parse({mediaType:`application/vnd.readium.lcp.license.v1.0+json`,name:`LCP License`,fileExtension:`lcpl`})}static get LCP_PROTECTED_AUDIOBOOK(){return e.parse({mediaType:`application/audiobook+lcp`,name:`LCP Protected Audiobook`,fileExtension:`lcpa`})}static get LCP_PROTECTED_PDF(){return e.parse({mediaType:`application/pdf+lcp`,name:`LCP Protected PDF`,fileExtension:`lcpdf`})}static get LCP_STATUS_DOCUMENT(){return e.parse({mediaType:`application/vnd.readium.license.status.v1.0+json`})}static get LPF(){return e.parse({mediaType:`application/lpf+zip`,fileExtension:`lpf`})}static get MP3(){return e.parse({mediaType:`audio/mpeg`,fileExtension:`mp3`})}static get MPEG(){return e.parse({mediaType:`video/mpeg`,fileExtension:`mpeg`})}static get NCX(){return e.parse({mediaType:`application/x-dtbncx+xml`,fileExtension:`ncx`})}static get OGG(){return e.parse({mediaType:`audio/ogg`,fileExtension:`oga`})}static get OGV(){return e.parse({mediaType:`video/ogg`,fileExtension:`ogv`})}static get OPDS1(){return e.parse({mediaType:`application/atom+xml;profile=opds-catalog`})}static get OPDS1_ENTRY(){return e.parse({mediaType:`application/atom+xml;type=entry;profile=opds-catalog`})}static get OPDS2(){return e.parse({mediaType:`application/opds+json`})}static get OPDS2_PUBLICATION(){return e.parse({mediaType:`application/opds-publication+json`})}static get OPDS_AUTHENTICATION(){return e.parse({mediaType:`application/opds-authentication+json`})}static get OPUS(){return e.parse({mediaType:`audio/opus`,fileExtension:`opus`})}static get OTF(){return e.parse({mediaType:`font/otf`,fileExtension:`otf`})}static get PDF(){return e.parse({mediaType:`application/pdf`,name:`PDF`,fileExtension:`pdf`})}static get PNG(){return e.parse({mediaType:`image/png`,fileExtension:`png`})}static get READIUM_AUDIOBOOK(){return e.parse({mediaType:`application/audiobook+zip`,name:`Readium Audiobook`,fileExtension:`audiobook`})}static get READIUM_AUDIOBOOK_MANIFEST(){return e.parse({mediaType:`application/audiobook+json`,name:`Readium Audiobook`,fileExtension:`json`})}static get READIUM_CONTENT_DOCUMENT(){return e.parse({mediaType:`application/vnd.readium.content+json`,name:`Readium Content Document`,fileExtension:`json`})}static get READIUM_GUIDED_NAVIGATION_DOCUMENT(){return e.parse({mediaType:`application/guided-navigation+json`,name:`Readium Guided Navigation Document`,fileExtension:`json`})}static get READIUM_POSITION_LIST(){return e.parse({mediaType:`application/vnd.readium.position-list+json`,name:`Readium Position List`,fileExtension:`json`})}static get READIUM_WEBPUB(){return e.parse({mediaType:`application/webpub+zip`,name:`Readium Web Publication`,fileExtension:`webpub`})}static get READIUM_WEBPUB_MANIFEST(){return e.parse({mediaType:`application/webpub+json`,name:`Readium Web Publication`,fileExtension:`json`})}static get SMIL(){return e.parse({mediaType:`application/smil+xml`,fileExtension:`smil`})}static get SVG(){return e.parse({mediaType:`image/svg+xml`,fileExtension:`svg`})}static get TEXT(){return e.parse({mediaType:`text/plain`,fileExtension:`txt`})}static get TIFF(){return e.parse({mediaType:`image/tiff`,fileExtension:`tiff`})}static get TTF(){return e.parse({mediaType:`font/ttf`,fileExtension:`ttf`})}static get W3C_WPUB_MANIFEST(){return e.parse({mediaType:`application/x.readium.w3c.wpub+json`,name:`Web Publication`,fileExtension:`json`})}static get WAV(){return e.parse({mediaType:`audio/wav`,fileExtension:`wav`})}static get WEBM_AUDIO(){return e.parse({mediaType:`audio/webm`,fileExtension:`webm`})}static get WEBM_VIDEO(){return e.parse({mediaType:`video/webm`,fileExtension:`webm`})}static get WEBP(){return e.parse({mediaType:`image/webp`,fileExtension:`webp`})}static get WOFF(){return e.parse({mediaType:`font/woff`,fileExtension:`woff`})}static get WOFF2(){return e.parse({mediaType:`font/woff2`,fileExtension:`woff2`})}static get XHTML(){return e.parse({mediaType:`application/xhtml+xml`,fileExtension:`xhtml`})}static get XML(){return e.parse({mediaType:`application/xml`,fileExtension:`xml`})}static get ZAB(){return e.parse({mediaType:`application/x.readium.zab+zip`,name:`Zipped Audio Book`,fileExtension:`zab`})}static get ZIP(){return e.parse({mediaType:`application/zip`,fileExtension:`zip`})}},O=(e=>(e.left=`left`,e.right=`right`,e.center=`center`,e))(O||{}),Ut=class e{constructor(e){this.otherProperties=e}get page(){return this.otherProperties.page}static deserialize(t){if(t)return new e(t)}serialize(){return this.otherProperties}add(t){let n=Object.assign({},this.otherProperties);for(let e in t)n[e]=t[e];return new e(n)}},Wt=class{constructor(e){this.uri=e,this.parameters=this.getParameters(e)}getParameters(e){let t=/\{\??([^}]+)\}/g,n=e.match(t);return n?new Set(n.join(`,`).replace(t,`$1`).split(`,`).map(e=>e.trim())):new Set}expand(e){let t=t=>t.split(`,`).map(t=>{let n=e[t];return n?encodeURIComponent(n):``}).join(`,`),n=t=>`?`+t.split(`,`).map(t=>{let n=t.split(`=`)[0],r=e[n];return r?`${n}=${encodeURIComponent(r)}`:``}).join(`&`);return this.uri.replace(/\{(\??)([^}]+)\}/g,(...e)=>e[1]?n(e[2]):t(e[2]))}},k=class e{constructor(e){this.fragments=e.fragments?e.fragments:[],this.progression=e.progression,this.totalProgression=e.totalProgression,this.position=e.position,this.otherLocations=e.otherLocations}static deserialize(t){if(!t)return;let n=f(t.progression),r=f(t.totalProgression),i=f(t.position),a=new Map,o=new Set([`fragment`,`fragments`,`progression`,`totalProgression`,`position`,`otherLocations`]);return Object.entries(t).forEach(([e,t])=>{o.has(e)||a.set(e,t)}),t.otherLocations instanceof Map&&t.otherLocations.forEach((e,t)=>a.set(t,e)),new e({fragments:u(t.fragments||t.fragment),progression:n!==void 0&&n>=0&&n<=1?n:void 0,totalProgression:r!==void 0&&r>=0&&r<=1?r:void 0,position:i!==void 0&&i>0?i:void 0,otherLocations:a.size===0?void 0:a})}serialize(){let e={};return this.fragments&&(e.fragments=this.fragments),this.progression!==void 0&&(e.progression=this.progression),this.totalProgression!==void 0&&(e.totalProgression=this.totalProgression),this.position!==void 0&&(e.position=this.position),this.otherLocations&&this.otherLocations.forEach((t,n)=>e[n]=t),e}},A=class e{constructor(e){this.after=e.after,this.before=e.before,this.highlight=e.highlight}static deserialize(t){if(t)return new e({after:t.after,before:t.before,highlight:t.highlight})}serialize(){let e={};return this.after!==void 0&&(e.after=this.after),this.before!==void 0&&(e.before=this.before),this.highlight!==void 0&&(e.highlight=this.highlight),e}},j=class e{constructor(e){let t=e.href.indexOf(`#`),n=t>=0?e.href.slice(t+1):void 0;this.href=t>=0?e.href.slice(0,t):e.href,this.type=e.type,this.title=e.title;let r=e.locations?.fragments,i=n&&(!r||r.length===0);this.locations=e.locations?i?new k({...e.locations,fragments:[n]}):e.locations:n?new k({fragments:[n]}):new k({}),this.text=e.text}static deserialize(t){if(t&&t.href&&t.type)return new e({href:t.href,type:t.type,title:t.title,locations:k.deserialize(t.locations),text:A.deserialize(t.text)})}serialize(){let e={href:this.href,type:this.type};return this.title!==void 0&&(e.title=this.title),this.locations&&(e.locations=this.locations.serialize()),this.text&&(e.text=this.text.serialize()),e}copyWithLocations(t){return new e({href:this.href,type:this.type,title:this.title,text:this.text,locations:new k({...this.locations,...t})})}},M=class e{constructor(e){this.href=e.href,this.templated=e.templated,this.type=e.type,this.title=e.title,this.rels=e.rels,this.properties=e.properties,this.height=e.height,this.width=e.width,this.size=e.size,this.duration=e.duration,this.bitrate=e.bitrate,this.languages=e.languages,this.alternates=e.alternates,this.children=e.children}static deserialize(t){if(t&&typeof t.href==`string`)return new e({href:t.href,templated:t.templated,type:t.type,title:t.title,rels:t.rel?Array.isArray(t.rel)?new Set(t.rel):new Set([t.rel]):void 0,properties:Ut.deserialize(t.properties),height:p(t.height),width:p(t.width),size:p(t.size),duration:p(t.duration),bitrate:p(t.bitrate),languages:u(t.language),alternates:N.deserialize(t.alternate),children:N.deserialize(t.children)})}serialize(){let e={href:this.href};return this.templated!==void 0&&(e.templated=this.templated),this.type!==void 0&&(e.type=this.type),this.title!==void 0&&(e.title=this.title),this.rels&&(e.rel=m(this.rels)),this.properties&&(e.properties=this.properties.serialize()),this.height!==void 0&&(e.height=this.height),this.width!==void 0&&(e.width=this.width),this.size!==void 0&&(e.size=this.size),this.duration!==void 0&&(e.duration=this.duration),this.bitrate!==void 0&&(e.bitrate=this.bitrate),this.languages&&(e.language=this.languages),this.alternates&&(e.alternate=this.alternates.serialize()),this.children&&(e.children=this.children.serialize()),e}get mediaType(){return this.type===void 0?Ht.BINARY:Ht.parse({mediaType:this.type})}toURL(e){let t=this.href.replace(/^(\/)/,``);if(t.length===0)return;let n=e||`/`;return n.startsWith(`/`)&&(n=`file://`+n),new URL(t,n).href.replace(/^(file:\/\/)/,``)}get templateParameters(){return this.templated?new Wt(this.href).parameters:new Set}expandTemplate(t){return new e({href:new Wt(this.href).expand(t),templated:!1})}addProperties(t){let n=e.deserialize(this.serialize());return n.properties=n.properties?n.properties?.add(t):new Ut(t),n}get locator(){return new j({href:this.href,type:this.type??``,title:this.title})}},N=class e{constructor(e){this.items=e}static deserialize(t){if(t&&Array.isArray(t))return new e(t.map(e=>M.deserialize(e)).filter(e=>e!==void 0))}serialize(){return this.items.map(e=>e.serialize())}findWithRel(e){return this.items.find(t=>t.rels&&t.rels.has(e))}filterByRel(e){return this.items.filter(t=>t.rels&&t.rels.has(e))}findWithHref(e){return this.items.find(t=>t.href===e)}findIndexWithHref(e){return this.items.findIndex(t=>t.href===e)}findWithMediaType(e){return this.items.find(t=>t.mediaType.matches(e))}filterByMediaType(e){return this.items.filter(t=>t.mediaType.matches(e))}filterByMediaTypes(e){return this.items.filter(t=>{for(let n of e)if(t.mediaType.matches(n))return!0;return!1})}everyIsAudio(){return this.items.length>0&&this.items.every(e=>e.mediaType.isAudio)}everyIsBitmap(){return this.items.length>0&&this.items.every(e=>e.mediaType.isBitmap)}everyIsHTML(){return this.items.length>0&&this.items.every(e=>e.mediaType.isHTML)}everyIsVideo(){return this.items.length>0&&this.items.every(e=>e.mediaType.isVideo)}everyMatchesMediaType(e){return Array.isArray(e)?this.items.length>0&&this.items.every(t=>{for(let n of e)return t.mediaType.matches(n);return!1}):this.items.length>0&&this.items.every(t=>t.mediaType.matches(e))}filterLinksHasType(){return this.items.filter(e=>e.type)}},Gt=class e{constructor(e){this.currency=e.currency,this.value=e.value}static deserialize(t){if(!t)return;let n=t.currency;if(!(n&&typeof n==`string`&&n.length>0))return;let r=p(t.value);if(r!==void 0)return new e({currency:n,value:r})}serialize(){return{currency:this.currency,value:this.value}}},Kt=class e{constructor(e){this.type=e.type,this.children=e.children}static deserialize(t){if(t&&t.type)return new e({type:t.type,children:e.deserializeArray(t.children)})}static deserializeArray(t){if(Array.isArray(t))return t.map(t=>e.deserialize(t)).filter(e=>e!==void 0)}serialize(){let e={type:this.type};return this.children&&(e.children=this.children.map(e=>e.serialize())),e}},qt=class e{constructor(e){this.total=e.total,this.position=e.position}static deserialize(t){if(t)return new e({total:p(t.total),position:p(t.position)})}serialize(){let e={};return this.total!==void 0&&(e.total=this.total),this.position!==void 0&&(e.position=this.position),e}},Jt=class e{constructor(e){this.total=e.total,this.available=e.available}static deserialize(t){if(t)return new e({total:p(t.total),available:p(t.available)})}serialize(){let e={};return this.total!==void 0&&(e.total=this.total),this.available!==void 0&&(e.available=this.available),e}},Yt=(e=>(e.available=`available`,e.reserved=`reserved`,e.ready=`ready`,e))(Yt||{}),Xt=class e{constructor(e){this.state=e.state,this.since=e.since,this.until=e.until}static deserialize(t){if(t&&t.state)return new e({state:t.state,since:d(t.since),until:d(t.until)})}serialize(){let e={state:this.state};return this.since!==void 0&&(e.since=this.since.toISOString()),this.until!==void 0&&(e.until=this.until.toISOString()),e}};function Zt(e){return p(e.otherProperties.numberOfItems)}function Qt(e){return Gt.deserialize(e.otherProperties.price)}function $t(e){let t=e.otherProperties.indirectAcquisition;if(t&&Array.isArray(t))return t.map(e=>Kt.deserialize(e)).filter(e=>e!==void 0)}function en(e){return qt.deserialize(e.otherProperties.holds)}function tn(e){return Jt.deserialize(e.otherProperties.copies)}function nn(e){return Xt.deserialize(e.otherProperties.availability)}function rn(e){return M.deserialize(e.otherProperties.authenticate)}function an(e){return e.linksWithRole(`images`)}var on=(e=>(e.EPUB=`https://readium.org/webpub-manifest/profiles/epub`,e.AUDIOBOOK=`https://readium.org/webpub-manifest/profiles/audiobook`,e.DIVINA=`https://readium.org/webpub-manifest/profiles/divina`,e.PDF=`https://readium.org/webpub-manifest/profiles/pdf`,e))(on||{}),sn=class e{constructor(e,t,n=[],r=[],i=void 0){this._trimmedLinkMap=new Map,this._allItems=e,this.linkMap=t,this._conformsTo=n,this.tocLinks=r,this._tocDepth=i}static build(t,n={}){let r=t.toc?.items??[],i=t.readingOrder.items,{depth:a}=n,o=t.metadata?.conformsTo??[],s=new Map,c=[];for(let t=0;t<i.length;t++){let n=i[t],o=e.bareHref(n.href),l=n.title??e.findTitleInToc(r,o,a),u=e.collectChildrenFromToc(r,o,a,1,s),d={title:l,references:[n.href],children:u.length>0?u:void 0};s.set(d,n),c.push(d)}return new e(c,s,o,r,a)}augment(e){for(let t of this.flatAll){let n=this.linkFor(t);if(!n)continue;let r=e(t,n);r.position!==void 0&&(t.position=r.position),r.scroll!==void 0&&(t.scroll=r.scroll),r.role!==void 0&&(t.role=r.role)}}get depth(){return this._depth}set depth(e){this._depth!==e&&(this._depth=e,this._tocDepth=e,this._items=void 0,this._flat=void 0,this._toc=void 0)}get items(){return this._items||(this._depth===void 0?this._items=this._allItems:(this._trimmedLinkMap=new Map,this._items=e.trimToDepth(this._allItems,this._depth,this.linkMap,this._trimmedLinkMap))),this._items}locate(e){let t=e.href.split(`#`)[0],n=Bt(e.locations),r=Rt(e.locations),i=e.locations.progression;if(n!==void 0){let e=-1/0,r;for(let i of this.flat){if(!this.itemMatchesHref(i,t))continue;let a=this.itemStartTime(i,t);a!==void 0&&a<=n&&a>e&&(e=a,r=i)}if(r)return r}if(r){let e=this.flat.find(e=>this.itemMatchesHref(e,t)?e.references.some(e=>e.split(`#`)[1]===r):!1);if(e)return e}if(i!==void 0){let e=-1/0,n;for(let r of this.flat){if(!this.itemMatchesHref(r,t))continue;let a=this.itemScrollPosition(r);a!==void 0&&a<=i&&a>e&&(e=a,n=r)}if(n)return n;let r=this.items.find(e=>this.itemMatchesHref(e,t));if(r?.children?.length&&!r.children.some(e=>e.scroll!==void 0)){let e=Math.min(Math.floor(i*r.children.length),r.children.length-1);return r.children[e]}}return this.flat.find(e=>this.itemMatchesHref(e,t))}navigableFrom(e){let t=this.flat.indexOf(e);return{previous:t>0?this.flat[t-1]:void 0,next:t>=0&&t<this.flat.length-1?this.flat[t+1]:void 0}}segmentsForHref(e){let t=e.split(`#`)[0],n=this.items.find(e=>this.itemMatchesHref(e,t));return n?n.children?.length?n.children:[n]:[]}ancestors(e){return this.ancestorPath(this.items,e)??[]}linkFor(e){return this.linkMap.get(e)??this._trimmedLinkMap.get(e)}get contextualizedToc(){return this._toc||=this.tocLinks.length>0?this.buildTocEntries(this.tocLinks,this._tocDepth,1):this._allItems.map(e=>this.entryFor(this.linkFor(e),e)),this._toc}tocEntryFor(e){let t=this.linkFor(e);return t?this.findTocEntryByLink(this.contextualizedToc,t)||this.nearestTocEntryForResource(t.href,e)||this.previousResolvedTocEntry(t):void 0}get flat(){return this._flat||=this.flattenItems(this.items),this._flat}get flatAll(){return this.flattenItems(this._allItems)}static findTitleInToc(t,n,r){let{atStart:i,fragments:a}=e.collectTocCandidates(t,n,r,1);if(i.length>0)return i[0].title;if(a.length===1)return a[0].title}static collectChildrenFromToc(t,n,r,i,a){if(r!==void 0&&i>r)return[];let o=[];for(let s of t){let t=e.bareHref(s.href),c=s.href.startsWith(`#`);if((t===n||c&&t===``)&&s.title&&!e.isStartOfResource(s.href)){let e=t===``?n+s.href:s.href,r={title:s.title,references:[e]};a.set(r,s),o.push(r)}s.children?.items?.length&&o.push(...e.collectChildrenFromToc(s.children.items,n,r,i+1,a))}return o}static collectTocCandidates(t,n,r,i){if(r!==void 0&&i>r)return{atStart:[],fragments:[]};let a=[],o=[];for(let s of t){let t=e.bareHref(s.href),c=s.href.startsWith(`#`);if((t===n||c&&t===``)&&s.title&&(e.isStartOfResource(s.href)?a.push(s):o.push(s)),s.children?.items?.length){let t=e.collectTocCandidates(s.children.items,n,r,i+1);a.push(...t.atStart),o.push(...t.fragments)}}return{atStart:a,fragments:o}}static isStartOfResource(e){let t=e.split(`#`)[1];if(!t)return!0;let n=t.match(/(?:^|&)t=([^&]+)/);return n!==null&&kt(n[1])}get linkToItem(){if(!this._linkToItem){this._linkToItem=new Map;for(let[e,t]of this.linkMap)this._linkToItem.set(t,e)}return this._linkToItem}buildTocEntries(e,t,n){return t!==void 0&&n>t?[]:e.map(e=>{let r=this.linkToItem.get(e)??this.resourceStartItem(e.href),i=e.children?.items?.length?this.buildTocEntries(e.children.items,t,n+1):[];return{...this.entryFor(e,r),children:i.length>0?i:void 0}})}tocLinksFlat(e,t,n){if(t!==void 0&&n>t)return[];let r=[];for(let i of e)r.push(i),i.children?.items?.length&&r.push(...this.tocLinksFlat(i.children.items,t,n+1));return r}entryFor(e,t){let n=this._conformsTo.includes(on.AUDIOBOOK);return{link:e,position:!n&&t?.position!==void 0?String(t.position):void 0,timestamp:n&&t?.position!==void 0?At(t.position):void 0}}resourceStartItem(t){let n=e.bareHref(t);return this._allItems.find(e=>this.itemMatchesHref(e,n))}findTocEntryByLink(e,t){for(let n of e){if(n.link===t)return n;if(n.children){let e=this.findTocEntryByLink(n.children,t);if(e)return e}}}nearestTocEntryForResource(t,n){let r=e.bareHref(t),i=this.tocLinksFlat(this.tocLinks,this._tocDepth,1).filter(t=>e.bareHref(t.href)===r).map(e=>({link:e,item:this.linkToItem.get(e)??this.resourceStartItem(e.href)}));if(i.length===0)return;let a=this._conformsTo.includes(on.AUDIOBOOK),o=a?n.position??0:n.scroll??0,s,c=-1/0;for(let e of i){let t=a?e.item?.position??0:e.item?.scroll??0;t<=o&&t>c&&(c=t,s=e)}let l=s??i[0];return this.findTocEntryByLink(this.contextualizedToc,l.link)}previousResolvedTocEntry(t){let n=this._allItems.findIndex(e=>this.linkFor(e)===t);if(n!==-1)for(let t=n-1;t>=0;t--){let n=this.linkFor(this._allItems[t]);if(!n)continue;let r=e.bareHref(n.href),{atStart:i,fragments:a}=e.collectTocCandidates(this.tocLinks,r,this._tocDepth,1),o=i.filter(t=>e.bareHref(t.href)===r),s=a.filter(t=>e.bareHref(t.href)===r),c=o[0]??(s.length>0?s[s.length-1]:void 0);if(!c)continue;let l=this.findTocEntryByLink(this.contextualizedToc,c);if(l)return l}}static trimToDepth(t,n,r,i){return t.map(t=>{let a={...t,children:n>1&&t.children?.length?e.trimToDepth(t.children,n-1,r,i):void 0},o=r.get(t);return o&&i.set(a,o),a})}flattenItems(e){let t=[];for(let n of e)t.push(n),n.children&&t.push(...this.flattenItems(n.children));return t}itemStartTime(e,t){for(let n of e.references){let e=n.indexOf(`#`),r=e>=0?n.slice(0,e):n,i=e>=0?n.slice(e+1):void 0;if((r||t)!==t)continue;if(!i)return;let a=i.match(/(?:^|&)t=([^&]+)/);return a?Ot(a[1]):void 0}}itemMatchesHref(e,t){return e.references.some(e=>{let n=e.split(`#`)[0];return n===t||n===``})}ancestorPath(e,t){for(let n of e){if(n===t)return[];if(n.children){let e=this.ancestorPath(n.children,t);if(e!==null)return[n,...e]}}return null}itemScrollPosition(e){return e.scroll}static bareHref(e){return e.split(`#`)[0]}};function cn(e,t){return sn.build(e,t)}function ln(e,t){let n=sn.build(e,t),r=e.readingOrder.items;if(!(r.length<=1||r.every(e=>e.duration!==void 0)))return n;let i=0,a=new Map(r.map(e=>{let t=i;return i+=e.duration??0,[e.href,t]}));return n.augment((e,t)=>{let n=t.href,r=n.indexOf(`#`),i=r>=0?n.slice(0,r):n,o=r>=0?n.slice(r+1):void 0,s=a.get(i)??0,c=o?.match(/(?:^|&)t=([^&]+)/);return{position:s+((c?Ot(c[1]):void 0)??0)}}),n}function un(e,t){return e.metadata?.conformsTo?.includes(on.AUDIOBOOK)??!1?ln(e,t):cn(e,t)}var dn=class{text(e=`
`){return this.elements().map(e=>e?.text).filter(e=>e!==void 0&&e.length>0).join(e)}elements(){let e=[],t=this.iterator();for(;t.hasNext();)e.push(t.next());return e}};function fn(e,t){return t.length>1?t.indexOf(e.slice(-1))>-1:e.slice(-1)===t}function pn(e,t){return e.slice(e.length-t.length)===t}var mn={endsWith:pn,endsWithChar:fn},hn=`ie.eg.ext.Fig.fig.Figs.figs.et al.Co.Corp.Ave.Inc.Ex.Viz.vs.Vs.repr.Rep.Dem.trans.Vol.pp.rev.est.Ref.Refs.Eq.Eqs.Ch.Sec.Secs.mi.Dept.Univ.Nos.No.Mol.Cell.Miss.Mrs.Mr.Ms.Prof.Dr.Sgt.Col.Gen.Rep.Sen.Gov.Lt.Maj.Capt.St.Sr.Jr.jr.Rev.PhD.MD.BA.MA.MM.BSc.MSc.Jan.Feb.Mar.Apr.Jun.Jul.Aug.Sep.Sept.Oct.Nov.Dec.Sun.Mon.Tu.Tue.Tues.Wed.Th.Thu.Thur.Thurs.Fri.Sat`.split(`.`);function gn(e){return/^[A-Z][a-z].*/.test(e)||Sn(e)}function _n(e){return gn(e)||/``|"|'/.test(e.substring(0,2))}function vn(e){return~hn.indexOf(e.replace(/\W+/g,``))}function yn(e,t){return!(e!==`a.m.`&&e!==`p.m.`||t.replace(/\W+/g,``).slice(-3).toLowerCase()!==`day`)}function bn(e){var t=e.replace(/[\(\)\[\]\{\}]/g,``).match(/(.\.)*/);return t&&t[0].length>0}function xn(e){return e.length<=3||gn(e)}function Sn(e,t){return t&&(e=e.slice(t-1,t+2)),!isNaN(Number(e))}function Cn(e){return e.match(/^(?:(?:\+?1\s*(?:[.-]\s*)?)?(?:\(\s*([2-9]1[02-9]|[2-9][02-8]1|[2-9][02-8][02-9])\s*\)|([2-9]1[02-9]|[2-9][02-8]1|[2-9][02-8][02-9]))\s*(?:[.-]\s*)?)?([2-9]1[02-9]|[2-9][02-9]1|[2-9][02-9]{2})\s*(?:[.-]\s*)?([0-9]{4})(?:\s*(?:#|x\.?|ext\.?|extension)\s*(\d+))?$/)}function wn(e){return e.match(/[-a-zA-Z0-9@:%._\+~#=]{2,256}\.[a-z]{2,6}\b([-a-zA-Z0-9@:%_\+.~#?&//=]*)/)}function Tn(e){var t=0;return((t=e.indexOf(`.`))>-1||(t=e.indexOf(`!`))>-1||(t=e.indexOf(`?`))>-1)&&e.charAt(t+1).match(/[a-zA-Z].*/)?[e.slice(0,t),e.charAt(t),e.slice(t+1)]:!1}function En(e){return e===`.`||e===`!`||e===`?`}function Dn(e,t){t=Object.assign(t||{},{newlineBoundary:t&&t.newlineBoundary||!0});var n=/\s/;return e.serie(e.re(n,{split:!0}),e.splitAndMerge(function(e,r,i,a,o,s){var c,l=[e,null],u=e,d=s.slice(o+1).find(function(e){return!n.test(e.value)});if(e===`
`&&t.newlineBoundary||En(e)||mn.endsWithChar(e,`?!`))return l;if(mn.endsWithChar(e,`.`)){if(d){if(e.length===2&&isNaN(e.charAt(0))&&e.match(/[a-zA-Z]/)||vn(e))return u;if(_n(d.value)){if(yn(e,d.value)||Sn(d.value)&&xn(e))return u}else if(mn.endsWith(e,`..`)||bn(e)||xn(e))return u}return l}let f;return(f=e.indexOf(`.`))>-1&&(Sn(e,f)||bn(e)||wn(e)||Cn(e))?u:(c=Tn(e))?[c[0]+c[1],null,c[2]]:u}),e.filter(function(e){return e.trim()!=``}))}var On=(e,...t)=>(...n)=>e(...t,...n);function kn(e){return{sentences:On(Dn,e)}}function An(e,t){return t?e.reduce(function(e,t){return[e,[t.index,t.offset,t.value].join(`-`)].join(`:`)},t):null}function jn(e){let{index:t,offset:n,value:r,...i}=e;return i}function Mn(e,t){var n=0;return Array.isArray(t)||(t=[t]),t.map(function(t){return t===null?null:(typeof t==`string`&&(t={value:t,index:n,offset:t.length}),typeof t==`object`&&(t.index=t.index||0,n=n+t.index+t.offset,t.index=e.index+t.index,t.offset=t.offset||t.value.length),t)})}function Nn(e,t){if(e.length==0)return null;var n=``,r=0,i=e[0]?.index;return e.forEach(function(a,o){var s=e[o-1];e[o+1];var c=s?a.index+1-(s.index+s.offset):0;n=n+Array(c).join(t)+a.value;var l=a.index-i+a.offset;l>r&&(r=l)}),{index:i,value:n,offset:Math.max(r,n.length)}}var Pn={tokensId:An,normalize:Mn,properties:jn,merge:Nn},Fn=RegExp(`([^	\r
\xA0 !"#$%&()*+,-.\\/:;<=>?@[\\]^_\`{|}~]+)`);function P(e){if(!(this instanceof P))return new P(e);this.opts=Object.assign({cacheGet:function(e){return null},cacheSet:function(e,t){}},e)}P.prototype.split=function(e,t={}){var n=this;return t=Object.assign({preserveProperties:!0,cache:()=>null},t),function(r,i){if(arguments.length===6)return e.apply(null,arguments);var a,o,s;if(r===void 0)return[];if(typeof r==`string`?r=[{value:r,index:0,offset:r.length}]:Array.isArray(r)||(r=[r]),o=Pn.tokensId(r,t.cache()),o&&(s=n.opts.cacheGet(o),s))return s;var c=r.map(function(n,i){var o=r[i+1],s=e(n.value,Object.assign({},n),a?Object.assign({},a):null,o?Object.assign({},o):null,i,r)||[];if(s=Pn.normalize(n,s),t.preserveProperties){var c=Pn.properties(n);s=s.map(function(e){return Object.assign({},e,c)})}return a=n,s}).filter(Boolean).flat();return o&&n.opts.cacheSet(o,c),c}},P.prototype.re=function(e,t={}){return t=Object.assign({split:!1},t),this.split(function(n,r){for(var i=n,a=[],o,s=0;o=e.exec(n);){var c=o.index,l=s+c,u=o[0]||``,d=u.length;if(t.split&&s<l){var f=i.slice(s,l);a.push({value:f,index:s,offset:f.length})}a.push({value:u,index:l,offset:d,match:o}),n=n.slice(c+d),s=l+d}return t.split&&n&&a.push({value:n,index:s,offset:n.length}),a},{cache:function(){return e.toString()}})},P.prototype.splitAndMerge=function(e,t={}){var n=this;return t=Object.assign({mergeWith:``},t),function(r){var i=[],a=[];function o(){if(a.length!=0){var e=Pn.merge(a,t.mergeWith);i.push(e),a=[]}}return n.split(function(t,n){var r=e.apply(null,arguments);r=Pn.normalize(n,r),r.forEach(function(e){e===null?o():a.push(e)})})(r),o(),i}},P.prototype.filter=function(e){return this.split(function(t,n){if(e.apply(null,arguments))return{value:n.value,index:0,offset:n.offset}})},P.prototype.extend=function(e){return this.split(function(t,n){var r=typeof e==`function`?e.apply(null,arguments):e;return Object.assign({value:n.value,index:0,offset:n.offset},r)})},P.prototype.ifthen=function(e,t){return this.split(function(n,r){if(e.apply(null,arguments))return t.apply(null,arguments);let{index:i,...a}=r;return a})},P.prototype.test=function(e){return this.filter(function(t,n){return e.test(t)},{cache:e.toString()})},P.prototype.flow=function(...e){let t=e.reduce((e,t)=>(...n)=>t(e(...n)));return this.split(t)},P.prototype.serie=function(...e){return e.reduce((e,t)=>(...n)=>t(e(...n)))},P.prototype.merge=function(){return this.splitAndMerge(e=>[e])},P.prototype.sections=function(){return this.re(/([^\n\.,;!?]+)/i,{split:!1})},P.prototype.words=function(){return this.re(Fn)},P.prototype.characters=function(){return this.re(/[^\s]/)};var In=(e=>(e.Word=`word`,e.Sentence=`sentence`,e.Paragraph=`paragraph`,e))(In||{}),Ln=(e,t)=>`Segmenter`in Intl?new Rn(e,t):new zn(e,t),Rn=class{constructor(e,t){if(this.unit=t,e??=navigator?.language,!(`Segmenter`in Intl))throw Error(`Intl.Segmenter is not supported in this environment`);if(t===`paragraph`)throw Error(`IntlTextTokenizer does not handle TextUnit.Paragraph`);this.segmenter=new Intl.Segmenter(e,{granularity:t})}tokenize(e){let t=this.segmenter.segment(e),n=[];for(let e of t){if(this.unit===`word`&&e.isWordLike===!1)continue;let t=Vn(e.segment);t!==null&&n.push([e.index,e.index+t.length])}return n}},zn=class{constructor(e,t){if(this.unit=t,e??=navigator?.language,this.isEnglish=e.toLowerCase().split(`-`)[0]===`en`,t===`paragraph`)throw Error(`NaiveTextTokenizer does not handle TextUnit.Paragraph`);this.tokenizer=new P}tokenize(e){let t=[];switch(this.unit){case`word`:t=this.tokenizer.words()(e);break;case`sentence`:t=this.isEnglish?kn(this.tokenizer).sentences()(e):this.tokenizer.sections()(e);break;default:t=[]}if(!t)return[];let n=[];return t.forEach(e=>{if(e.value.length===0)return;let t=Vn(e.value);t!==null&&n.push([e.index,e.index+t.length])}),n}},Bn=RegExp(`[\\p{L}\\p{N}]+`,`u`),Vn=e=>{let t=e.trimEnd();return t.length===0||t.match(Bn)===null?null:t},Hn=class{constructor(e,t){this.key=e,this.value=t}},Un=(e=>(e.ACCESSIBILITY_LABEL=`accessibilityLabel`,e.LANGUAGE=`language`,e))(Un||{}),Wn=class{constructor(e=[]){this._attributes=e}get language(){return this.attribute(`language`)}get accessibilityLabel(){return this.attribute(`accessibilityLabel`)}attribute(e){return this._attributes.find(t=>t.key===e)?.value}attributes(e){return this._attributes.filter(t=>t.key===e).map(e=>e.value)}},Gn=class extends Wn{constructor(e,t=[]){super(t),this.locator=e}},Kn=class extends Gn{get text(){return this.accessibilityLabel}},qn=class extends Kn{constructor(e,t,n=[]){super(e,n),this.embeddedLink=t}},Jn=class extends Kn{constructor(e,t,n=[]){super(e,n),this.embeddedLink=t}},Yn=class extends Kn{constructor(e,t,n,r=[]){super(e,r),this.embeddedLink=t,this.caption=n}get text(){return(this.caption?.length||0)>0?this.caption:super.text}},Xn=class extends Wn{constructor(e,t,n=[]){super(n),this.locator=e,this.text=t}},Zn=class extends Kn{constructor(e,t,n,r=[]){super(e,r),this.role=t,this.segments=n}get text(){return this.segments.map(e=>e.text).join(``)}},Qn=class{constructor(e,t,n=50,r=e=>Ln(e,t)){this.defaultLanguage=e,this.contextSnippetLength=n,this.textTokenizerFactory=r}tokenize(e){return e instanceof Zn?[new Zn(e.locator,e.role,e.segments.map(e=>this.tokenizeSegment(e)).flat())]:[e]}tokenizeSegment(e){return this.textTokenizerFactory(e.language??this.defaultLanguage).tokenize(e.text).map(t=>new Xn(new j({href:e.locator.href,type:e.locator.type,title:e.locator.title,locations:e.locator.locations,text:this.extractTextContextIn(e.text,t)}),e.text.substring(t[0],t[1]),e._attributes))}extractTextContextIn(e,t){let n=e.substring(t[1],t[1]+this.contextSnippetLength),r=e.substring(t[0]-this.contextSnippetLength,t[0]);return new A({after:n.length>0?n:void 0,before:r.length>0?r:void 0,highlight:e.substring(t[0],t[1])})}},$n=class extends Error{constructor(e){super(e)}},er=class{async nextOrNull(){return await this.hasNext()?this.next():null}async previousOrNull(){return await this.hasPrevious()?this.previous():null}},tr=class{constructor(e){this.level=e}get role(){return`heading-${this.level}`}},nr={role:`body`},rr={role:`footnote`},ir=class{constructor(e,t){this.referenceUrl=e,this.referenceTitle=t,this.role=`quote`}},ar=class{constructor(e,t){this.index=e,this.iterator=t}async nextContentIn(e){return e===1?this.iterator.nextOrNull():this.iterator.previousOrNull()}},or=class{constructor(e,t){this.element=e,this.direction=t}},sr=class extends er{constructor(e,t,n){super(),this.publication=e,this.startLocator=t,this.resourceContentIteratorFactories=n,this._currentIterator=null,this.currentElement=null}async hasPrevious(){return this.currentElement=await this.nextIn(-1),this.currentElement!==null}previous(){if(this.currentElement?.direction!==-1)throw new $n(`Called previous() without a successful call to hasPrevious() first`);return this.currentElement.element}async hasNext(){return this.currentElement=await this.nextIn(1),this.currentElement!==null}next(){if(this.currentElement?.direction!==1)throw new $n(`Called next() without a successful call to hasNext() first`);return this.currentElement.element}async nextIn(e){let t=this.currentIterator;if(!t)return null;let n=await t.nextContentIn(e);if(!n){let n=this.nextIteratorIn(e,t.index);return n?(this._currentIterator=n,this.nextIn(e)):null}return new or(n,e)}get currentIterator(){return this._currentIterator||=this.initialIterator(),this._currentIterator}initialIterator(){let e=this.startLocator?this.publication.readingOrder.findIndexWithHref(this.startLocator.href):0,t=this.startLocator||0;return this.loadIteratorAt(e,t)??this.nextIteratorIn(1,e)}nextIteratorIn(e,t){let n=t+e;if(n<0||n>=this.publication.manifest.readingOrder.items.length)return null;let r=e===1?0:1;return this.loadIteratorAt(n,r)??this.nextIteratorIn(e,n)}loadIteratorAt(e,t){let n=this.publication.readingOrder.items[e],r=typeof t==`number`?this.publication.manifest.locatorFromLink(n)?.copyWithLocations({progression:t}):t;if(!r)return null;let i=this.publication.get(n);for(let t of this.resourceContentIteratorFactories){let n=t(i,r);if(n)return new ar(e,n)}return null}},cr=class extends Gn{constructor(e,t,n=[]){super(e,n),this.element=t}get text(){return this.element.text}},lr=class{constructor(e,t){this.element=e,this.direction=t}},ur=class extends er{constructor(e,t){super(),this.pageContent=e,this.startLocator=t,this.pageContentFiltered=[],this.currentElement=null,this.currentProgression=0,this.currentElementIndex=0;let n=this.pageContent.filter(e=>e?.str!==` `&&e?.str!==``);if(this.pageContentFiltered=n.map(e=>new cr(e.locator,{index:n.indexOf(e),text:e.str,readingDirection:e.dir})),this.startLocator&&(this.currentProgression=this.startLocator?.locations?.progression||0,this.updateElementIndex()),this.pageContentFiltered.length>0){let e=this.currentElementIndex;(e||e===0)&&(this.currentElement=new lr(this.pageContentFiltered[e],1))}}current(){return this.currentElement?this.currentElement.element:null}async hasPrevious(){return this.currentElement?.direction,this.nextIn(-1)!==null}previous(){if(!this.currentElement)throw new $n(`Called next() without a successful call to hasNext() first`);if(this.currentElement=this.nextIn(-1),this.currentElementIndex&&this.currentElementIndex>0){let e=this.currentElementIndex-1;this.currentProgression=e/this.pageContentFiltered.length*100,this.currentElementIndex=e}return this.currentElement?this.currentElement.element:new cr(new j({href:``,type:``}),{index:-1,text:``})}async hasNext(){return this.currentElement?.direction,this.nextIn(1)!==null}next(){this.currentElement=this.nextIn(1);let e=this.currentElementIndex;if(e!==null&&e>=0&&e<this.pageContentFiltered.length-1){let t=e+1;this.currentProgression=t/this.pageContentFiltered.length*100,this.currentElementIndex=t}return this.currentElement?this.currentElement.element:new cr(new j({href:``,type:``}),{index:-1,text:``})}nextIn(e){let t=this.currentElementIndex;if(t===null||t===this.pageContentFiltered.length-1&&e===1||t===0&&e===-1)return null;let n=this.pageContentFiltered[t+e];return n?new lr(n,e):null}updateElementIndex(){return this.currentProgression===0?0:this.currentProgression<0||this.currentProgression>=100?null:Math.floor(this.currentProgression*this.pageContentFiltered.length/100)}},dr=`OBJECT.BASE.FONT.TT.I.B.U.BIG.SMALL.EM.STRONG.DFN.CODE.SAMP.KBD.VAR.CITE.ABBR.TIME.ACRONYM.MARK.RUBY.RT.RP.RTC.A.IMG.BR.WBR.MAP.Q.SUB.SUP.BDO.IFRAME.EMBED.SPAN.INPUT.SELECT.TEXTAREA.LABEL.BUTTON.OPTGROUP.OPTION.LEGEND.DATALIST.KEYGEN.OUTPUT.PROGRESS.METER.AREA.PARAM.SOURCE.TRACK.SUMMARY.COMMAND.DEVICE.BASEFONT.BGSOUND.MENUITEM.DATA.BDI.S.STRIKE.NOBR.RB`.split(`.`);function fr(e){return dr.includes(e.nodeName.toUpperCase())}function pr(e,t){let n=e.getAttribute(`src`);if(!n?.length)return null;try{return new URL(n,t).toString()}catch{return n}}var mr=`[\\s\\u0085\\u00A0\\u2000-\\u200A\\u2028\\u2029\\u202F\\u205F\\u3000]`,hr=RegExp(`^${mr}+$`,`g`),gr=RegExp(`^${mr}+|${mr}+$/g`,`g`),_r=RegExp(`^${mr}+`,`g`),vr=RegExp(`${mr}+$`,`g`),yr=e=>!e?.length||hr.test(e),br=e=>e.replace(gr,``),xr=e=>e.replace(_r,``),Sr=e=>e.replace(vr,``),Cr=(e,t=``)=>new A({before:t+(_r.exec(e)?.[0]??``),highlight:br(e),after:vr.exec(e)?.[0]??``});function wr(e){for(;e;){let t=e.getAttribute(`lang`)||e.getAttributeNS(`http://www.w3.org/1999/xhtml`,`lang`)||e.getAttributeNS(`http://www.w3.org/XML/1998/namespace`,`lang`);if(t)return t;e=e.parentElement}return null}function Tr(e,t){let n=e.length>0&&e[e.length-1]===` `,r=!1,i=!1;for(let a=0;a<t.length;a++)if(yr(t[a])){if(n&&!i||r)continue;e+=` `,r=!0}else{let n=t.charCodeAt(a);n!==8203&&n!==173&&(e+=t[a],r=!1,i=!0)}return e}function Er(e){return typeof e==`object`&&!!e&&e.nodeType===Node.ELEMENT_NODE}var Dr={NONE:``,DESCENDANT:` `,CHILD:` > `},F={id:`id`,class:`class`,tag:`tag`,attribute:`attribute`,nthchild:`nthchild`,nthoftype:`nthoftype`};function Or(e,t){return Object.values(e).includes(t)}var kr=`CssSelectorGenerator`;function Ar(e=`unknown problem`,...t){console.warn(`${kr}: ${e}`,...t)}var jr={selectors:[F.id,F.class,F.tag,F.attribute],includeTag:!1,whitelist:[],blacklist:[],combineWithinSelector:!0,combineBetweenSelectors:!0,root:null,maxCombinations:1/0,maxCandidates:1/0,useScope:!1};function Mr(e){return Array.isArray(e)?e.filter(e=>Or(F,e)):[]}function Nr(e){return e instanceof RegExp}function Pr(e){return[`string`,`function`].includes(typeof e)||Nr(e)}function Fr(e){return Array.isArray(e)?e.filter(Pr):[]}function Ir(e){return e instanceof Node}function Lr(e){let t=[Node.DOCUMENT_NODE,Node.DOCUMENT_FRAGMENT_NODE,Node.ELEMENT_NODE];return Ir(e)&&t.includes(e.nodeType)}function Rr(e,t){if(Lr(e))return e.contains(t)||Ar(`element root mismatch`,"Provided root does not contain the element. This will most likely result in producing a fallback selector using element's real root node. If you plan to use the selector using provided root (e.g. `root.querySelector`), it will not work as intended."),e;let n=t.getRootNode({composed:!1});return Lr(n)?(n!==document&&Ar(`shadow root inferred`,"You did not provide a root and the element is a child of Shadow DOM. This will produce a selector using ShadowRoot as a root. If you plan to use the selector using document as a root (e.g. `document.querySelector`), it will not work as intended."),n):Jr(t)}function zr(e){return typeof e==`number`?e:1/0}function Br(e,t={}){let n=Object.assign(Object.assign({},jr),t);return{selectors:Mr(n.selectors),whitelist:Fr(n.whitelist),blacklist:Fr(n.blacklist),root:Rr(n.root,e),combineWithinSelector:!!n.combineWithinSelector,combineBetweenSelectors:!!n.combineBetweenSelectors,includeTag:!!n.includeTag,maxCombinations:zr(n.maxCombinations),maxCandidates:zr(n.maxCandidates),useScope:!!n.useScope,maxResults:zr(n.maxResults)}}function Vr(e=[]){let[t=[],...n]=e;return n.length===0?t:n.reduce((e,t)=>e.filter(e=>t.includes(e)),t)}function Hr(e){return[].concat(...e)}function Ur(e){return e.replace(/[|\\{}()[\]^$+?.]/g,`\\$&`).replace(/\*/g,`.+`)}function Wr(e){let t=e.map(e=>{if(Nr(e))return t=>e.test(t);if(typeof e==`function`)return t=>{let n=e(t);return typeof n==`boolean`?n:(Ar(`pattern matcher function invalid`,`Provided pattern matching function does not return boolean. It's result will be ignored.`,e),!1)};if(typeof e==`string`){let t=RegExp(`^`+Ur(e)+`$`);return e=>t.test(e)}return Ar(`pattern matcher invalid`,`Pattern matching only accepts strings, regular expressions and/or functions. This item is invalid and will be ignored.`,e),()=>!1});return e=>t.some(t=>t(e))}function Gr(e,t,n){let r=Array.from(Rr(n,e[0]).querySelectorAll(t));return r.length===e.length&&e.every(e=>r.includes(e))}function Kr(e,t){t??=Jr(e);let n=[],r=e;for(;Er(r)&&r!==t;)n.push(r),r=r.parentElement;return n}function qr(e,t){return Vr(e.map(e=>Kr(e,t)))}function Jr(e){return e.ownerDocument.querySelector(`:root`)}var Yr=new RegExp([`^$`,`\\s`].join(`|`)),Xr=new RegExp([`^$`].join(`|`)),Zr=[F.nthoftype,F.tag,F.id,F.class,F.attribute,F.nthchild],Qr=Wr([`class`,`id`,`ng-*`]);function $r({name:e}){return`[${e}]`}function ei({name:e,value:t}){return`[${e}='${t}']`}function ti({nodeName:e,nodeValue:t},n){let r=n.tagName.toLowerCase();return[`input`,`option`].includes(r)&&e===`value`||e===`src`&&t?.startsWith(`data:`)?!1:!Qr(e)}function ni({nodeName:e,nodeValue:t}){return{name:xi(e),value:xi(t??void 0)}}function ri(e){let t=Array.from(e.attributes).filter(t=>ti(t,e)).map(ni);return[...t.map($r),...t.map(ei)]}function ii(e){return Vr(e.map(ri))}function ai(e){return(e.getAttribute(`class`)??``).trim().split(/\s+/).filter(e=>!Xr.test(e)).map(e=>`.${xi(e)}`)}function oi(e){return Vr(e.map(ai))}function si(e){let t=e.getAttribute(`id`)??``,n=`#${xi(t)}`,r=e.getRootNode({composed:!1});return!Yr.test(t)&&Gr([e],n,r)?[n]:[]}function ci(e){return e.length===0||e.length>1?[]:si(e[0])}function li(e){let t=e.parentElement?.children;if(t){for(let n=0;n<t.length;n++)if(t[n]===e)return[`:nth-child(${String(n+1)})`]}return[]}function ui(e){return Vr(e.map(li))}function di(e){return[xi(e.tagName.toLowerCase())]}function fi(e){let t=[...new Set(Hr(e.map(di)))];return t.length===0||t.length>1?[]:[t[0]]}function pi(e){let t=fi([e])[0],n=e.parentElement;if(n){let r=Array.from(n.children).filter(e=>e.tagName.toLowerCase()===t).indexOf(e);if(r>-1)return[`${t}:nth-of-type(${String(r+1)})`]}return[]}function mi(e){return Vr(e.map(pi))}function*hi(e=[],{maxResults:t=1/0}={}){let n=0,r=vi(1);for(;r.length<=e.length&&n<t;)n+=1,yield r.map(t=>e[t]),r=_i(r,e.length-1)}function gi(e=[],{maxResults:t=1/0}={}){return Array.from(hi(e,{maxResults:t}))}function _i(e=[],t=0){let n=e.length;if(n===0)return[];let r=[...e];r[n-1]+=1;for(let e=n-1;e>=0;e--)if(r[e]>t){if(e===0)return vi(n+1);r[e-1]++,r[e]=r[e-1]+1}return r[n-1]>t?vi(n+1):r}function vi(e=1){return Array.from(Array(e).keys())}function*yi(e={}){let t=Object.entries(e);if(t.length===0)return;let n=[{index:t.length-1,partial:{}}];for(;n.length>0;){let e=n.pop();if(!e)break;let{index:r,partial:i}=e;if(r<0){yield i;continue}let[a,o]=t[r];for(let e=o.length-1;e>=0;e--)n.push({index:r-1,partial:Object.assign(Object.assign({},i),{[a]:o[e]})})}}var bi=/[ !"#$%&'()\[\]{|}<>*+,./;=?@^`~\\]/;function xi(e=``){return CSS?CSS.escape(e):Si(e)}function Si(e=``){return e.split(``).map(e=>e===`:`?`\\3A `:bi.test(e)?`\\${e}`:escape(e).replace(/%/g,`\\`)).join(``)}var Ci={tag:fi,id:ci,class:oi,attribute:ii,nthchild:ui,nthoftype:mi},wi={tag:di,id:si,class:ai,attribute:ri,nthchild:li,nthoftype:pi};function Ti(e,t){return wi[t](e)}function Ei(e,t){let n=Ci[t];return n(e)}function Di(e=[],t,n){return e.filter(e=>n(e)||!t(e))}function Oi(e=[],t){return e.sort((e,n)=>{let r=t(e),i=t(n);return r&&!i?-1:!r&&i?1:0})}function*ki(e,t){let n=new Set,r=Ai(e,t);for(let e of Pi(r,t))n.has(e)||(n.add(e),yield e)}function Ai(e,t){let{blacklist:n,whitelist:r,combineWithinSelector:i,maxCombinations:a}=t,o=Wr(n),s=Wr(r);return ji(t).reduce((t,n)=>{let r=Oi(Di(Ei(e,n),o,s),s);return t[n]=i?Array.from(hi(r,{maxResults:a})):r.map(e=>[e]),t},{})}function ji(e){let{selectors:t,includeTag:n}=e,r=[...t];return n&&!r.includes(`tag`)&&r.push(`tag`),r}function Mi(e){return e.includes(F.tag)||e.includes(F.nthoftype)?[...e]:[...e,F.tag]}function Ni(e){let{selectors:t,combineBetweenSelectors:n,includeTag:r,maxCandidates:i}=e,a=n?gi(t,{maxResults:i}):t.map(e=>[e]);return r?a.map(Mi):a}function*Pi(e,t){for(let n of Ni(t))yield*Fi(n,e)}function*Fi(e,t){let n={};for(let r of e){let e=t[r];e&&e.length>0&&(n[r]=e)}for(let e of yi(n))yield Li(e)}function Ii(e,t){return t[e]?t[e].join(``):``}function Li(e={}){let t=[...Zr];return e[F.tag]&&e[F.nthoftype]&&t.splice(t.indexOf(F.tag),1),t.map(t=>Ii(t,e)).join(``)}function Ri(e,t){return[...e.map(e=>t+Dr.DESCENDANT+e),...e.map(e=>t+Dr.CHILD+e)]}function*zi(e,t){if(t===``)yield*e;else for(let n of e)yield*Ri([n],t)}function*Bi(e,t,n=``,r){let i=ki(e,r);for(let r of zi(i,n))Gr(e,r,t)&&(yield r)}function*Vi(e,t,n=``,r){if(e.length===0)return null;let i=[e.length>1?e:[],...qr(e,t).map(e=>[e])];for(let e of i)for(let i of Bi(e,t,n,r))yield{foundElements:e,selector:i}}function*Hi({elements:e,root:t,rootSelector:n=``,options:r}){let i=t,a=n,o=!0;for(;o;){let n=!1;for(let o of Vi(e,i,a,r)){let{foundElements:r,selector:s}=o;if(n=!0,Gr(e,s,t))yield s;else{i=r[0],a=s;break}}n||(o=!1)}}function Ui(e){(e instanceof NodeList||e instanceof HTMLCollection)&&(e=Array.from(e));let t=(Array.isArray(e)?e:[e]).filter(Er);return[...new Set(t)]}function Wi(e){return{value:e,include:!1}}function Gi(e,t,n=Dr.NONE){let r={};return t.forEach(t=>{Reflect.set(r,t,Ti(e,t).map(Wi))}),{element:e,operator:n,selectors:r}}function Ki({selectors:e,operator:t}){let n=[...Zr];e[F.tag]&&e[F.nthoftype]&&(n=n.filter(e=>e!==F.tag));let r=``;return n.forEach(t=>{(e[t]??[]).forEach(({value:e,include:t})=>{t&&(r+=e)})}),t+r}function qi(e,t){let n=Kr(e,t).reverse().map(e=>{let t=Gi(e,[F.nthchild],Dr.CHILD);return(t.selectors.nthchild??[]).forEach(e=>{e.include=!0}),t});return[t?`:scope`:`:root`,...n.map(Ki)].join(``)}function Ji(e,t){return e.map(e=>qi(e,t)).join(`, `)}function Yi(e,t={}){return Xi(e,Object.assign(Object.assign({},t),{maxResults:1})).next().value}function*Xi(e,t={}){let n=Ui(e),r=Br(n[0],t),i=r.root??Jr(n[0]),a=0;for(let e of Hi({elements:n,options:r,root:i,rootSelector:``}))if(yield e,a++,a>=r.maxResults)return;n.length>1&&(yield n.map(e=>Yi(e,r)).join(`, `),a++,a>=r.maxResults)||(yield Ji(n,r.useScope?i:void 0))}var Zi=class extends er{constructor(e,t,n=50){super(),this.resource=e,this.locator=t,this.beforeMaxLength=n,this.currentElement=null,this.currentIndex=null,this.parsedElementRecipes=null,this.parser=null}async hasPrevious(){if(this.currentElement?.delta===-1)return!0;let e=await this.elements(),t=(this.currentIndex??e.startIndex)-1,n=e.elements.at(t);return n?(this.currentIndex=t,this.currentElement={delta:-1,element:this.parser.executeRecipe(n)},!0):!1}previous(){if(!this.currentElement||this.currentElement.delta!==-1)throw new $n(`Called previous() without a successful call to hasPrevious() first`);let e=this.currentElement.element;return this.currentElement=null,e}async hasNext(){if(this.currentElement?.delta===1)return!0;let e=await this.elements(),t=(this.currentIndex??e.startIndex-1)+1,n=e.elements.at(t);return n?(this.currentIndex=t,this.currentElement={delta:1,element:this.parser.executeRecipe(n)},!0):!1}next(){if(!this.currentElement||this.currentElement.delta!==1)throw new $n(`Called next() without a successful call to hasNext() first`);let e=this.currentElement.element;return this.currentElement=null,e}async elements(){return this.parsedElementRecipes??=await this.parseElements(),this.parsedElementRecipes}async parseElements(){let e=await this.resource.readAsString(),t=new DOMParser().parseFromString(e,this.locator.type),n=Nt(this.locator.locations);return this.parser=new $i(t,this.locator,n?t.querySelector(n):null,this.beforeMaxLength),Qi(this.parser,t.body),this.parser.result()}};function Qi(e,t){let n=t,r=0;for(;n!=null;)if(e.head(n,r),n.firstChild!=null)n=n.firstChild,r++;else{for(;n?.nextSibling==null&&r>0;)n&&e.tail(n,r),n=n?.parentNode||null,r--;if(n&&e.tail(n,r),n===t)break;n=n?.nextSibling||null}}var $i=class{constructor(e,t,n,r){this.doc=e,this.baseLocator=t,this.startElement=n,this.beforeMaxLength=r,this.elementRecipes=[],this.startIndex=0,this.segmentRecipesAcc=[],this.textAcc=``,this.wholeRawTextAcc=null,this.elementRawTextAcc=``,this.rawTextAcc=``,this.currentLanguage=null,this.breadcrumbs=[],this.recipeCssSelectorCache=new WeakMap}result(){return{elements:this.elementRecipes,startIndex:this.baseLocator.locations.progression===1?this.elementRecipes.length:this.startIndex}}executeRecipe(e){let t=e.recipe.cssSelectorNode?this.cssSelector(e.recipe.cssSelectorNode):null;if(e.type===1){let n=e.recipe;return new Yn(new j({href:this.baseLocator.href,type:this.baseLocator.type,title:this.baseLocator.title,locations:new k(t?{otherLocations:new Map([[`cssSelector`,t]])}:{})}),new M({href:n.href}),n.caption,n.attributes)}if(e.type===2||e.type===3){let n=new j({href:this.baseLocator.href,type:this.baseLocator.type,title:this.baseLocator.title,locations:new k(t?{otherLocations:new Map([[`cssSelector`,t]])}:{})}),r=e.recipe;return e.type===3?new Jn(n,r.link):new qn(n,r.link)}if(e.type===0){let n=e.recipe,r=n.segments.map(e=>{let t=e.cssSelectorNode?this.cssSelector(e.cssSelectorNode):null;return new Xn(new j({href:this.baseLocator.href,type:this.baseLocator.type,title:this.baseLocator.title,text:Cr(e.text,this.wholeRawTextAcc?.substring(e.beforeRange[0],e.beforeRange[1])),locations:new k(t?{otherLocations:new Map([[`cssSelector`,t]])}:{})}),e.text,e.attributes)});return new Zn(new j({href:this.baseLocator.href,type:this.baseLocator.type,title:this.baseLocator.title,text:Cr(n.text,r.length&&r[0].locator.text?.before||``),locations:new k(t?{otherLocations:new Map([[`cssSelector`,t]])}:{})}),n.role,r)}throw Error(`Unknown recipe type`)}cssSelector(e){let t=e,n=this.recipeCssSelectorCache.get(t);if(n)return n;let r=new Map,i=t;for(;i&&i!==this.doc.body;){for(let e=0;e<i.attributes.length;e++){let t=i.attributes[e];t.prefix&&(r.has(i)?r.set(i,r.get(i).concat([t])):r.set(i,[t]),i.attributes.removeNamedItem(t.name))}i=i.parentElement}let a=Yi(t,{root:this.doc});return r.forEach((e,t)=>e.forEach(e=>t.attributes.setNamedItem(e))),this.recipeCssSelectorCache.set(t,a),a}head(e,t){if(e.nodeType==Node.ELEMENT_NODE){let t=!fr(e);t&&(this.flushText(),this.breadcrumbs.push(e));let n=e.nodeName.toUpperCase();if(n===`BR`)this.flushText();else if(n===`IMG`||n===`AUDIO`||n===`VIDEO`){if(this.flushText(),n===`IMG`){let t=e,n=pr(t,this.baseLocator.href),r=t.getAttribute(`alt`);r?.length||(r=t.getAttribute(`title`)),n!=null&&this.elementRecipes.push({type:1,recipe:{href:n,caption:void 0,cssSelectorNode:e,attributes:r?.length?[new Hn(Un.ACCESSIBILITY_LABEL,r)]:[]}})}else{let t=e,r=pr(t,this.baseLocator.href),i;if(r!=null)i=new M({href:r});else{let e=[...t.getElementsByTagName(`source`)].map(e=>{let t=pr(e,this.baseLocator.href);return t?new M({href:t,type:e.getAttribute(`type`)||void 0}):null}).filter(e=>!!e);e.length>0&&(i=new M({href:e[0].href,type:e[0].type,alternates:e.length>1?new N(e.slice(1)):void 0}))}i&&(n===`AUDIO`?this.elementRecipes.push({type:2,recipe:{cssSelectorNode:e,link:i}}):n===`VIDEO`&&this.elementRecipes.push({type:3,recipe:{cssSelectorNode:e,link:i}}))}}t&&this.flushText()}}tail(e,t){if(e.nodeType===Node.TEXT_NODE&&!yr(e.textContent)){let t=wr(e.parentElement);this.currentLanguage!==t&&(this.flushSegment(),this.currentLanguage=t),this.rawTextAcc+=e.textContent,this.textAcc=Tr(this.textAcc,e.textContent)}else if(e.nodeType===Node.ELEMENT_NODE&&!fr(e)){if(!this.breadcrumbs.length||this.breadcrumbs.at(-1)!==e)throw Error(`HTMLContentIterator: breadcrumbs mismatch`);this.flushText(),this.breadcrumbs.pop()}}flushText(){if(this.flushSegment(),this.startIndex===0&&this.startElement&&this.breadcrumbs.length&&this.breadcrumbs.at(-1)===this.startElement&&(this.startIndex=this.elementRecipes.length),!this.segmentRecipesAcc.length)return;this.segmentRecipesAcc[this.segmentRecipesAcc.length-1].text=Sr(this.segmentRecipesAcc[this.segmentRecipesAcc.length-1].text);let e=nr;if(this.breadcrumbs.length>0){let t=this.breadcrumbs.at(-1);if(t.getAttributeNS(`http://www.idpf.org/2007/ops`,`type`)===`footnote`)e=rr;else switch(t.nodeName.toUpperCase()){case`H1`:case`H2`:case`H3`:case`H4`:case`H5`:case`H6`:e=new tr(parseInt(t.nodeName[1]));break;case`BLOCKQUOTE`:case`Q`:e=new ir(t.getAttribute(`cite`)?.length?new URL(t.getAttribute(`cite`)):void 0,t.getAttribute(`title`)||void 0)}}this.elementRecipes.push({type:0,recipe:{text:this.elementRawTextAcc,role:e,segments:[...this.segmentRecipesAcc],cssSelectorNode:this.breadcrumbs.at(-1)}}),this.elementRawTextAcc=``,this.segmentRecipesAcc=[]}flushSegment(){let e=this.textAcc,t=br(e);yr(t)||(this.segmentRecipesAcc.length||(e=xr(e),e=t+(e.length&&yr(e[e.length-1])?e[e.length-1]:``)),this.segmentRecipesAcc.push({text:e,attributes:this.currentLanguage?[new Hn(Un.LANGUAGE,this.currentLanguage)]:[],beforeRange:this.wholeRawTextAcc?[this.wholeRawTextAcc.length-this.beforeMaxLength,this.wholeRawTextAcc.length]:[0,0],cssSelectorNode:this.breadcrumbs.at(-1)})),this.rawTextAcc.length&&(this.wholeRawTextAcc=(this.wholeRawTextAcc||``)+this.rawTextAcc,this.elementRawTextAcc+=this.rawTextAcc),this.rawTextAcc=``,this.textAcc=``}},ea=class e{constructor(e){this.value=e.value,this.scheme=e.scheme}static deserialize(t){if(t){if(typeof t==`string`)return new e({value:t});if(typeof t==`object`&&t.value)return new e({value:t.value,scheme:t.scheme})}}serialize(){return this.scheme?{value:this.value,scheme:this.scheme}:this.value}},ta=class e{constructor(t){this.translations=typeof t==`string`?{[e.UNDEFINED_LANGUAGE]:t}:t}static deserialize(t){if(t&&(typeof t==`string`||t.constructor===Object))return new e(t)}serialize(){return this.translations}getTranslation(t){return this.translations[t||e.UNDEFINED_LANGUAGE]||this.translations[e.UNDEFINED_LANGUAGE]||this.translations[e.LANGUAGE_EN]||(Object.values(this.translations).length===0?``:Object.values(this.translations)[0])}};ta.UNDEFINED_LANGUAGE=`und`,ta.LANGUAGE_EN=`en`;var I=ta,na=class e{constructor(e){this.name=e.name,this.sortAs=e.sortAs,this.identifier=e.identifier,this.altIdentifiers=e.altIdentifiers,this.roles=e.roles,this.links=e.links,this.position=e.position}static deserialize(t){if(t)return typeof t==`string`?new e({name:I.deserialize(t)}):t.name?new e({name:I.deserialize(t.name),sortAs:I.deserialize(t.sortAs),identifier:t.identifier,altIdentifiers:t.altIdentifier?Array.isArray(t.altIdentifier)?new Set(t.altIdentifier.map(e=>ea.deserialize(e)).filter(e=>e!==void 0)):new Set([ea.deserialize(t.altIdentifier)].filter(e=>e!==void 0)):void 0,roles:t.role?new Set(u(t.role)):void 0,links:N.deserialize(t.links),position:f(t.position)}):void 0}serialize(){let e={name:this.name.serialize()};return this.sortAs!==void 0&&(e.sortAs=this.sortAs.serialize()),this.identifier!==void 0&&(e.identifier=this.identifier),this.altIdentifiers&&(e.altIdentifier=m(this.altIdentifiers).map(e=>e.serialize())),this.roles&&(e.role=m(this.roles)),this.links&&(e.links=this.links.serialize()),this.position!==void 0&&(e.position=this.position),e}},L=class e{constructor(e){this.items=e}static deserialize(t){if(t)return new e((Array.isArray(t)?t:[t]).map(e=>na.deserialize(e)).filter(e=>e!==void 0))}serialize(){return this.items.map(e=>e.serialize())}},ra=class e{constructor(e){this.items=e&&e.items?e.items:new Map}static deserialize(t){if(!(t&&typeof t==`object`))return;let n=new Map;return Object.entries(t).forEach(([e,t])=>{let r=L.deserialize(t);r&&r.items.length>0&&n.set(e,r)}),new e({items:n})}serialize(){let e={};return this.items.forEach((t,n)=>e[n]=t.serialize()),e}},ia=class e{constructor(e){this.title=e.title,this.numberOfItems=e.numberOfItems,this.otherMetadata=e.otherMetadata}static deserialize(t){if(!t)return;let n=new Map,r=new Set([`title`,`numberOfItems`]);return Object.entries(t).forEach(([e,t])=>{r.has(e)||n.set(e,t)}),new e({title:I.deserialize(t.title),numberOfItems:f(t.numberOfItems),otherMetadata:n.size===0?void 0:n})}serialize(){let e={};return this.title&&(e.title=this.title.serialize()),this.numberOfItems!==void 0&&(e.numberOfItems=this.numberOfItems),this.otherMetadata&&this.otherMetadata.forEach((t,n)=>e[n]=t),e}},aa=class e{constructor(e){this.metadata=e.metadata??new ia({}),this.links=e.links??new N([]),this.locators=e.locators??[]}static deserialize(t){if(!t)return;let n,r=t.locators;return r&&Array.isArray(r)&&(n=r.map(e=>j.deserialize(e)).filter(e=>e!==void 0)),new e({metadata:ia.deserialize(t.metadata),links:N.deserialize(t.links),locators:n})}serialize(){let e={};if(this.metadata){let t=this.metadata.serialize();t&&Object.keys(t).length>0&&(e.metadata=t)}return this.links&&this.links.items.length>0&&(e.links=this.links.serialize()),this.locators&&(e.locators=this.locators.map(e=>e.serialize())),e}},R=(e=>(e.ltr=`ltr`,e.rtl=`rtl`,e))(R||{});function oa(e){return e===`rtl`?O.right:O.left}var sa=class e{constructor(e){this.name=e.name,this.sortAs=e.sortAs,this.code=e.code,this.scheme=e.scheme,this.links=e.links}static deserialize(t){if(t)return typeof t==`string`?new e({name:I.deserialize(t)}):t.name?new e({name:I.deserialize(t.name),sortAs:t.sortAs?I.deserialize(t.sortAs):void 0,code:t.code,scheme:t.scheme,links:N.deserialize(t.links)}):void 0}serialize(){let e={name:this.name.serialize()};return this.sortAs!==void 0&&(e.sortAs=this.sortAs.serialize()),this.code!==void 0&&(e.code=this.code),this.scheme!==void 0&&(e.scheme=this.scheme),this.links&&(e.links=this.links.serialize()),e}},ca=class e{constructor(e){this.items=e}static deserialize(t){if(t)return new e((Array.isArray(t)?t:[t]).map(e=>sa.deserialize(e)).filter(e=>e!==void 0))}serialize(){return this.items.map(e=>e.serialize())}},la=(e=>(e.all=`all`,e.none=`none`,e))(la||{}),ua=class e{constructor(e){this.reservation=e.reservation,this.policy=e.policy}static deserialize(t){if(t)return new e({reservation:t.reservation,policy:t.policy})}serialize(){let e={};return this.reservation!==void 0&&(e.reservation=this.reservation),this.policy!==void 0&&(e.policy=this.policy),e}},da=class e{constructor(e){this.title=e.title,this.typeUri=e.typeUri,this.conformsTo=e.conformsTo,this.identifier=e.identifier,this.altIdentifier=e.altIdentifier,this.subtitle=e.subtitle,this.sortAs=e.sortAs,this.artists=e.artists,this.authors=e.authors,this.colorists=e.colorists,this.contributors=e.contributors,this.editors=e.editors,this.illustrators=e.illustrators,this.inkers=e.inkers,this.letterers=e.letterers,this.narrators=e.narrators,this.pencilers=e.pencilers,this.translators=e.translators,this.languages=e.languages,this.description=e.description,this.publishers=e.publishers,this.imprints=e.imprints,this.published=e.published,this.modified=e.modified,this.subjects=e.subjects,this.belongsTo=e.belongsTo,this.belongsToCollections=e.belongsToCollections,this.belongsToSeries=e.belongsToSeries,this.belongsToCollections&&this.belongsToCollections.items.length>0&&(this.belongsTo||=new ra,this.belongsTo.items.set(`collection`,this.belongsToCollections)),this.belongsToSeries&&this.belongsToSeries.items.length>0&&(this.belongsTo||=new ra,this.belongsTo.items.set(`series`,this.belongsToSeries)),this.layout=e.layout,this.readingProgression=e.readingProgression,this.duration=e.duration,this.numberOfPages=e.numberOfPages,this.accessibility=e.accessibility,this.tdm=e.tdm,this.otherMetadata=e.otherMetadata}static deserialize(t){if(!(t&&t.title))return;let n=I.deserialize(t.title),r=t[`@type`],i=u(t.conformsTo),a=t.identifier,o=ea.deserialize(t.altIdentifier),s=I.deserialize(t.subtitle),c=I.deserialize(t.sortAs),l=L.deserialize(t.artist),f=L.deserialize(t.author),m=L.deserialize(t.colorist),g=L.deserialize(t.contributor),ee=L.deserialize(t.editor),te=L.deserialize(t.illustrator),_=L.deserialize(t.inker),v=L.deserialize(t.letterer),y=L.deserialize(t.narrator),ne=L.deserialize(t.penciler),b=L.deserialize(t.translator),x=u(t.language),S=t.description,C=L.deserialize(t.publisher),w=L.deserialize(t.imprint),re=d(t.published),ie=d(t.modified),ae=ca.deserialize(t.subject),oe=ra.deserialize(t.belongsTo),T=h.deserialize(t.accessibility),se=t.layout,ce=t.readingProgression,le=p(t.duration),ue=p(t.numberOfPages),de=ua.deserialize(t.tdm),fe=Object.assign({},t);return e.mappedProperties.forEach(e=>delete fe[e]),Object.keys(fe).length===0&&(fe=void 0),new e({title:n,typeUri:r,conformsTo:i,identifier:a,altIdentifier:o,subtitle:s,sortAs:c,artists:l,authors:f,colorists:m,contributors:g,editors:ee,illustrators:te,inkers:_,letterers:v,narrators:y,pencilers:ne,translators:b,languages:x,description:S,publishers:C,imprints:w,published:re,modified:ie,subjects:ae,belongsTo:oe,layout:se,readingProgression:ce,duration:le,numberOfPages:ue,accessibility:T,tdm:de,otherMetadata:fe})}serialize(){let e={title:this.title.serialize()};if(this.typeUri!==void 0&&(e[`@type`]=this.typeUri),this.conformsTo&&(e.conformsTo=this.conformsTo),this.identifier!==void 0&&(e.identifier=this.identifier),this.altIdentifier&&(e.altIdentifier=this.altIdentifier.serialize()),this.subtitle&&(e.subtitle=this.subtitle.serialize()),this.sortAs&&(e.sortAs=this.sortAs.serialize()),this.editors&&(e.editor=this.editors.serialize()),this.artists&&(e.artist=this.artists.serialize()),this.authors&&(e.author=this.authors.serialize()),this.colorists&&(e.colorist=this.colorists.serialize()),this.contributors&&(e.contributor=this.contributors.serialize()),this.illustrators&&(e.illustrator=this.illustrators.serialize()),this.letterers&&(e.letterer=this.letterers.serialize()),this.narrators&&(e.narrator=this.narrators.serialize()),this.pencilers&&(e.penciler=this.pencilers.serialize()),this.translators&&(e.translator=this.translators.serialize()),this.inkers&&(e.inker=this.inkers.serialize()),this.languages&&(e.language=this.languages),this.description!==void 0&&(e.description=this.description),this.publishers&&(e.publisher=this.publishers.serialize()),this.imprints&&(e.imprint=this.imprints.serialize()),this.published!==void 0&&(e.published=this.published.toISOString()),this.modified!==void 0&&(e.modified=this.modified.toISOString()),this.subjects&&(e.subject=this.subjects.serialize()),this.belongsTo&&(e.belongsTo=this.belongsTo.serialize()),this.layout&&(e.layout=this.layout),this.readingProgression&&(e.readingProgression=this.readingProgression),this.duration!==void 0&&(e.duration=this.duration),this.numberOfPages!==void 0&&(e.numberOfPages=this.numberOfPages),this.accessibility&&(e.accessibility=this.accessibility.serialize()),this.tdm&&(e.tdm=this.tdm.serialize()),this.otherMetadata){let t=this.otherMetadata;Object.keys(t).forEach(n=>e[n]=t[n])}return e}get effectiveLayout(){if(!this.conformsTo)return null;for(let e of this.conformsTo)switch(e){case on.EPUB:return this.layout||D.reflowable;case on.DIVINA:return this.layout===D.reflowable?D.fixed:this.layout||D.fixed;case on.AUDIOBOOK:case on.PDF:return null}return null}get effectiveReadingProgression(){if(this.readingProgression)return this.readingProgression;if(this.languages?.length!==1)return R.ltr;let e=this.languages[0].toLowerCase();if(e===`zh-hant`||e===`zh-tw`)return R.rtl;switch(e.split(`-`)[0]){case`ar`:return R.rtl;case`fa`:return R.rtl;case`he`:return R.rtl;default:return R.ltr}}};da.mappedProperties=`title.@type.conformsTo.identifier.altIdentifier.subtitle.sortAs.artist.author.colorist.contributor.editor.illustrator.inker.letterer.narrator.penciler.translator.language.description.publisher.imprint.published.modified.subject.belongsTo.layout.readingProgression.duration.numberOfPages.accessibility.tdm`.split(`.`);var fa=da,pa=class e{constructor(e){this.metadata=e.metadata,this.links=e.links,this.subcollections=e.subcollections}static deserialize(t){if(!t)return;let n,r,i;if(Array.isArray(t))n=N.deserialize(t);else if(typeof t==`object`)n=N.deserialize(t.links),r=new Map,t.metadata&&Object.entries(t.metadata).forEach(([e,t])=>{r?.set(e,t)}),i=e.deserializeCollections(t);else return;if(n&&n.items.length!==0)return new e({metadata:r?.size?r:void 0,links:n,subcollections:i?.size?i:void 0})}static deserializeCollections(t){if(!t)return;let n=new Map;return Object.entries(t).forEach(([t,r])=>{if(t!==`links`&&t!==`metadata`){let i=e.deserialize(r);if(i){let e=[];e.push(i),n.set(t,e)}else if(Array.isArray(r)){let i=r.map(t=>e.deserialize(t)).filter(e=>e!==void 0);n.set(t,i)}}}),n.size?n:void 0}serialize(){let t={};return this.metadata&&(t.metadata={},this.metadata.forEach((e,n)=>t.metadata[n]=e)),this.links.items.length&&(t.links=this.links.serialize()),e.serializeCollection(t,this.subcollections),t}static serializeCollection(e,t){t&&t.size>0&&t.forEach((t,n)=>{e[n]=t.length===1?t[0].serialize():t.map(e=>e.serialize())})}},ma=class e{constructor(e){this.context=e.context,this.metadata=e.metadata,this.links=e.links||new N([]),this.readingOrder=e.readingOrder,this.resources=e.resources,this.toc=e.toc,this.subcollections=e.subcollections}static deserialize(t){if(!t)return;let n=fa.deserialize(t.metadata);if(!n)return;let r=N.deserialize(t.readingOrder?t.readingOrder:t.spine);if(!r)return;let i=new Set([`@context`,`metadata`,`links`,`readingOrder`,`spine`,`resources`,`toc`]),a={};return Object.keys(t).forEach(e=>{i.has(e)||(a[e]=t[e])}),new e({context:u(t[`@context`]),metadata:n,links:N.deserialize(t.links),readingOrder:r,resources:N.deserialize(t.resources),toc:N.deserialize(t.toc),subcollections:pa.deserializeCollections(a)})}serialize(){let e={};return this.context!==void 0&&(e[`@context`]=this.context),e.metadata=this.metadata.serialize(),this.links&&this.links.items.length>0&&(e.links=this.links.serialize()),e.readingOrder=this.readingOrder.serialize(),this.resources&&(e.resources=this.resources.serialize()),this.toc&&(e.toc=this.toc.serialize()),pa.serializeCollection(e,this.subcollections),e}linkWithRel(e){let t=[];t.push(this.readingOrder),this.resources&&t.push(this.resources),this.links&&t.push(this.links);let n;for(let r of t)if(n=r.findWithRel(e),n!==void 0)return n;return n}linksWithRel(e){let t=[];return t.push(this.readingOrder.filterByRel(e)),this.resources&&t.push(this.resources.filterByRel(e)),this.links&&t.push(this.links.filterByRel(e)),t.reduce((e,t)=>e.concat(t),[])}locatorFromLink(e){let t=e.href.split(`#`)[0],n=this.linkWithHref(t);if(!n)return;let r=n.type;if(!r)return;let i=e.href.includes(`#`);return new j({href:e.href,type:r,title:n.title??e.title,locations:new k({progression:i?void 0:0})})}linkWithHref(e){let t=n=>{let r;for(let t of n)if(r=t.findWithHref(e),r!==void 0)return r;let i=[];return n.forEach(e=>{let t=[];for(let n of e.items)n.alternates&&t.push(n.alternates),n.children&&t.push(n.children);i.push(...t)}),i.length>0&&(r=t(i)),r},n=[];n.push(this.readingOrder),this.resources&&n.push(this.resources),this.links&&n.push(this.links);let r=t(n);if(r!==void 0)return r;let i=e.split(/[#]/);if(i.length<2)return;let a=i[0];return this.linkWithHref(a)}get baseURL(){let e=this.links?.items.find(e=>e.rels&&e.rels.has(`self`));if(!e)return;let t=e.href;if(t)try{let e=new URL(t);return e.search=``,e.hash=``,e.pathname=e.pathname.substring(0,e.pathname.lastIndexOf(`/`)+1),e.href}catch{return t.split(/[?#]/)[0].replace(/[^/]*$/,``)}}setSelfLink(e){this.links||=new N([]),this.links.items=this.links.items.filter(e=>e.rels===void 0||!e.rels?.has(`self`)),this.links.items.push(new M({href:e,type:Ht.READIUM_WEBPUB_MANIFEST.string,rels:new Set([`self`])}))}},ha=class e{constructor(e){this.guided=e.guided}static deserialize(t){if(!t)return;let n=va.deserializeArray(t.guided);if(n&&n.length!==0)return new e({guided:n})}serialize(){return{guided:this.guided.map(e=>e.serialize())}}},ga=class e{constructor(e){this.plain=e.plain,this.ssml=e.ssml,this.language=e.language}static deserialize(t){if(t!=null){if(typeof t==`string`)return t.length>0?new e({plain:t}):void 0;if(t.plain||t.ssml)return new e({plain:t.plain,ssml:t.ssml,language:t.language})}}serialize(){let e={};return this.plain!==void 0&&(e.plain=this.plain),this.ssml!==void 0&&(e.ssml=this.ssml),this.language!==void 0&&(e.language=this.language),Object.keys(e).length>0?e:void 0}},_a=class e{constructor(e){this.audioref=e.audioref,this.imgref=e.imgref,this.textref=e.textref,this.videoref=e.videoref,this.text=e.text}static deserialize(t){if(!t)return;let n=new e({audioref:t.audioref,imgref:t.imgref,textref:t.textref,videoref:t.videoref,text:ga.deserialize(t.text)});if(n.audioref!==void 0||n.imgref!==void 0||n.textref!==void 0||n.videoref!==void 0||n.text!==void 0)return n}serialize(){let e={};this.audioref!==void 0&&(e.audioref=this.audioref),this.imgref!==void 0&&(e.imgref=this.imgref),this.textref!==void 0&&(e.textref=this.textref),this.videoref!==void 0&&(e.videoref=this.videoref);let t=this.text?.serialize();return t!==void 0&&(e.text=t),e}},va=class e{constructor(e){this.id=e.id,this.audioref=e.audioref,this.children=e.children,this.imgref=e.imgref,this.role=e.role,this.text=e.text,this.textref=e.textref,this.videoref=e.videoref,this.description=e.description}get plainText(){return this.text?.plain}get ssmlText(){return this.text?.ssml}get textLanguage(){return this.text?.language}static deserialize(t){if(!t)return;let n=e.deserializeArray(t.children),r=new e({id:typeof t.id==`string`?t.id:void 0,audioref:t.audioref,children:n&&n.length>0?n:void 0,imgref:t.imgref,role:t.role?new Set(u(t.role)):void 0,text:ga.deserialize(t.text),textref:t.textref,videoref:t.videoref,description:_a.deserialize(t.description)});if(r.audioref!==void 0||r.imgref!==void 0||r.textref!==void 0||r.videoref!==void 0||r.text!==void 0||r.children!==void 0)return r}static deserializeArray(t){if(Array.isArray(t))return t.map(t=>e.deserialize(t)).filter(e=>e!==void 0)}serialize(){let e={};if(this.id!==void 0&&(e.id=this.id),this.audioref!==void 0&&(e.audioref=this.audioref),this.children!==void 0&&(e.children=this.children.map(e=>e.serialize())),this.imgref!==void 0&&(e.imgref=this.imgref),this.role!==void 0&&(e.role=m(this.role)),this.text!==void 0){let t=this.text.serialize();t!==void 0&&(e.text=t)}return this.textref!==void 0&&(e.textref=this.textref),this.videoref!==void 0&&(e.videoref=this.videoref),this.description!==void 0&&(e.description=this.description.serialize()),e}get audioFile(){return this.audioref?.split(`#`)[0]}get audioTime(){if(this.audioref?.includes(`#`))return this.audioref.split(`#`,2)[1]}get textFile(){return this.textref?.split(`#`)[0]}get fragmentId(){if(this.textref?.includes(`#`))return this.textref.split(`#`,2)[1]}get clip(){let e=this.audioFile;if(!e)return;let t=this.audioTime,n={audioResource:e,fragmentId:this.fragmentId};if(!t)return n;let r=this.parseTimer(t);return n.start=r[0],n.end=r[1],n}parseTimer(e){if(!e||!e.startsWith(`t=`))return[void 0,void 0];let t=e.substring(2).split(`,`).map(e=>parseFloat(e));return t.length===1?[isNaN(t[0])?void 0:t[0],void 0]:t.length>2?[void 0,void 0]:[isNaN(t[0])?void 0:t[0],isNaN(t[1])?void 0:t[1]]}},ya=class{constructor(e){this.fetcher=new i,e.fetcher&&(this.fetcher=e.fetcher),this.manifest=e.manifest,this.context=e.manifest.context,this.metadata=e.manifest.metadata,this.links=e.manifest.links,this.readingOrder=e.manifest.readingOrder,this.resources=e.manifest.resources,this.toc=e.manifest.toc,this.subcollections=e.manifest.subcollections}get timeline(){return this._timeline||=un(this),this._timeline}get baseURL(){return this.manifest.baseURL}linkWithHref(e){return this.manifest.linkWithHref(e)}linksWithRole(e){let t=this.subcollections?.get(e);return t&&t.length>0?t[0].links:void 0}linksWithRel(e){return this.manifest.linksWithRel(e)}linkWithRel(e){return this.manifest.linkWithRel(e)}getCover(){let e=[this.links,this.resources,this.readingOrder].filter(Boolean);for(let t of e){let e=t.items.find(e=>e.rels?.has(`cover`));if(e)return e}for(let t of e){let e=t.items.find(e=>e.mediaType.isBitmap||e.mediaType.matches(Ht.SVG));if(e)return e}}async positionsFromManifest(){let e=this.manifest.links?.findWithMediaType(`application/vnd.readium.position-list+json`);if(e===void 0)return[];let t=await this.get(e).readAsJSON();return t.total?t.positions.map(e=>j.deserialize(e)).filter(e=>e!==void 0):[]}async guideForLink(e){let t=e=>e.alternates?.findWithMediaType(`application/guided-navigation+json`),n=t(e);if(!n){let r=this.linkWithHref(e.href);r!==void 0&&(n=t(r))}if(n||=this.manifest.links?.findWithMediaType(`application/guided-navigation+json`),!n)return;let r=n.href;if(n.templated){let t=new Wt(r),n={};t.parameters.has(`ref`)&&(n.ref=e.href),r=new Wt(r).expand(n)}let i=await this.get(new M({href:r})).readAsJSON();return ha.deserialize(i)}get(e){return this.fetcher.get(e)}},ba=r({AccessMode:()=>v,Accessibility:()=>h,AccessibilityMetadataDisplayGuide:()=>mt,AccessibilityProfile:()=>ee,AccessibilitySummary:()=>pt,Acquisition:()=>Kt,AdditionalInformation:()=>ct,AltIdentifier:()=>ea,Attribute:()=>Hn,AttributeKeys:()=>Un,AttributesHolder:()=>Wn,AudioElement:()=>qn,Availability:()=>Xt,AvailabilityStatus:()=>Yt,BelongsTo:()=>ra,Body:()=>nr,Certification:()=>te,Conformance:()=>dt,Content:()=>dn,ContentElement:()=>Gn,Contributor:()=>na,Contributors:()=>L,Copies:()=>Jt,DefaultTextContentTokenizer:()=>Ln,DomRange:()=>Dt,DomRangePoint:()=>Et,EmptyFetcher:()=>i,Encryption:()=>ht,Exemption:()=>re,Feature:()=>x,Footnote:()=>rr,GuidedNavigationDescription:()=>_a,GuidedNavigationDocument:()=>ha,GuidedNavigationObject:()=>va,GuidedNavigationText:()=>ga,HTMLResourceContentIterator:()=>Zi,Hazard:()=>C,HazardType:()=>lt,Hazards:()=>ut,Heading:()=>tr,Holds:()=>qt,HttpFetcher:()=>a,HttpResource:()=>o,IllegalStateError:()=>$n,ImageElement:()=>Yn,IntlTextTokenizer:()=>Rn,Iterator:()=>er,Layout:()=>D,Legal:()=>ft,Link:()=>M,Links:()=>N,Localization:()=>E,LocalizedString:()=>I,Locator:()=>j,LocatorCollection:()=>aa,LocatorCollectionMetadata:()=>ia,LocatorLocations:()=>k,LocatorText:()=>A,Manifest:()=>ma,MediaOverlay:()=>_t,MediaType:()=>Ht,Metadata:()=>fa,NaiveTextTokenizer:()=>zn,Navigation:()=>at,NonvisualReading:()=>nt,NumberRange:()=>s,PDFContentElement:()=>cr,Page:()=>O,PageContentIteratorPDF:()=>ur,PrerecordedAudio:()=>rt,Price:()=>Gt,PrimaryAccessMode:()=>ne,Profile:()=>on,Properties:()=>Ut,Publication:()=>ya,PublicationCollection:()=>pa,PublicationContentIterator:()=>sr,ReadingProgression:()=>R,Resource:()=>c,RichContent:()=>st,RichContentType:()=>ot,Subject:()=>sa,Subjects:()=>ca,TDM:()=>ua,TDMReservation:()=>la,TextContentTokenizer:()=>Qn,TextElement:()=>Zn,TextQuote:()=>ir,TextSegment:()=>Xn,TextUnit:()=>In,TextualElement:()=>Kn,Timeline:()=>sn,URITemplate:()=>Wt,VideoElement:()=>Jn,VisualAdjustments:()=>tt,WaysOfReading:()=>it,arrayfromJSON:()=>l,arrayfromJSONorString:()=>u,buildAudioTimeline:()=>ln,buildHtmlTimeline:()=>cn,buildTimeline:()=>un,datefromJSON:()=>d,formatNptTime:()=>At,getAuthenticate:()=>rn,getAvailability:()=>nn,getContains:()=>yt,getCopies:()=>tn,getCssSelector:()=>Nt,getDomRange:()=>Ft,getEncryption:()=>gt,getFragmentParameters:()=>Lt,getHolds:()=>en,getHtmlId:()=>Rt,getImages:()=>an,getIndirectAcquisitions:()=>$t,getLandmarks:()=>xt,getListOfAudioClips:()=>St,getListOfIllustrations:()=>Ct,getListOfTables:()=>wt,getListOfVideoClips:()=>Tt,getMediaOverlay:()=>vt,getNumberOfItems:()=>Zt,getPage:()=>zt,getPageList:()=>bt,getPartialCfi:()=>Pt,getPrice:()=>Qt,getSpace:()=>Vt,getTextFragment:()=>It,getTime:()=>Bt,isNptStartOfResource:()=>kt,leadingPage:()=>oa,numberfromJSON:()=>f,parseNptTime:()=>Ot,positiveNumberfromJSON:()=>p,setToArray:()=>m,speakableToken:()=>Vn}),xa=2**32,Sa=()=>Math.round(Math.random()*xa).toString(36),Ca=()=>`${Math.round(performance.now())}-${Sa()}-${Sa()}`,wa=class{constructor(e){this.destination=null,this.registrar=new Map,this.origin=``,this.channelId=``,this.receiver=this.receive.bind(this),this.preLog=[],this.wnd=e,e.addEventListener(`message`,this.receiver)}receive(e){if(e.source===null)throw Error(`Event source is null`);if(typeof e.data!=`object`)return;let t=e.data;if(!(!(`_readium`in t)||!t._readium||t._readium<=0)){if(t.key===`_ping`){if(!this.destination){if(this.destination=e.source,this.origin=e.origin,this.channelId=t._channel,t._readium!==1){t._readium>1?this.send(`error`,`received comms version ${t._readium} higher than 1`):this.send(`error`,`received comms version ${t._readium} lower than 1`),this.destination=null,this.origin=``,this.channelId=``;return}this.send(`_pong`,void 0),this.preLog.forEach(e=>this.send(`log`,e)),this.preLog=[]}return}if(this.channelId){if(t._channel!==this.channelId||e.origin!==this.origin)return}else return;this.handle(t)}}handle(e){let t=this.registrar.get(e.key);!t||t.length===0?e.strict&&this.send(`_unhandled`,e):t.forEach(t=>t.cb(e.data,t=>{this.send(`_ack`,t,e.id)}))}register(e,t,n){Array.isArray(e)||(e=[e]),e.forEach(e=>{let r=this.registrar.get(e);if(r&&r.length>=0){if(r.find(e=>e.module===t))throw Error(`Trying to register another callback for combination of event ${e} and module ${t}`);r.push({cb:n,module:t}),this.registrar.set(e,r)}else this.registrar.set(e,[{cb:n,module:t}])})}unregister(e,t){Array.isArray(e)||(e=[e]),e.forEach(e=>{let n=this.registrar.get(e);!n||n.length===0||n.splice(n.findIndex(e=>e.module===t),1)})}unregisterAll(e){this.registrar.forEach((t,n)=>this.registrar.set(n,t.filter(t=>t.module!==e)))}log(...e){this.destination?this.send(`log`,e):this.preLog.push(e)}get ready(){return!!this.destination}destroy(){this.destination=null,this.channelId=``,this.preLog=[],this.registrar.clear(),this.wnd.removeEventListener(`message`,this.receiver)}send(e,t,n=void 0,r=[]){if(!this.destination)throw Error(`Attempted to send comms message before destination has been initialized`);let i={_readium:1,_channel:this.channelId,id:n??Ca(),key:e,data:t};try{this.destination.postMessage(i,{targetOrigin:this.origin,transfer:r})}catch(e){if(r.length>0)throw e;this.destination.postMessage(i,this.origin,r)}}},Ta=class{},Ea=`readium-snapper-style`,Da=class e extends Ta{constructor(){super(...arguments),this.protected=!1,this.timelineEntries=new Map,this.cachedFragmentIds=[],this.sortedFragmentIds=[],this.cachedFragmentStarts=new Map}static inDomOrder(e,t,n){let r=e.get(t),i=e.get(n);return!r||!i?0:r.compareDocumentPosition(i)&Node.DOCUMENT_POSITION_FOLLOWING?-1:1}updateTimelineEntries(t,n){this.cachedFragmentIds=t,this.timelineEntries.clear(),this.cachedFragmentStarts.clear();for(let e of t){let t=n.document.getElementById(e);t&&this.timelineEntries.set(e,t)}this.sortedFragmentIds=Array.from(this.timelineEntries.keys()).sort((t,n)=>e.inDomOrder(this.timelineEntries,t,n)),this.refreshFragmentStarts()}refreshFragmentStarts(){for(let[e,t]of this.timelineEntries)this.cachedFragmentStarts.set(e,this.fragmentStart(t))}fragmentStart(e){return 0}currentScrollExtent(){return{pos:0,size:0}}nearestPrecedingTimelineEntry(e){let t;for(let n of this.sortedFragmentIds){let r=this.timelineEntries.get(n),i=r.compareDocumentPosition(e);if(r===e||r.contains(e)||(i&Node.DOCUMENT_POSITION_FOLLOWING)!==0)t=n;else break}return t}fragmentFromGeometry(){for(let e of this.sortedFragmentIds){let t=this.timelineEntries.get(e);if(this.inCenterBand(t))return e}let e;for(let t of this.sortedFragmentIds){let n=this.timelineEntries.get(t);if(this.hasScrolledPast(n))e=t;else break}return e}firstFragmentIfReached(){let e=this.sortedFragmentIds[0];if(e===void 0)return;let t=this.timelineEntries.get(e);return this.hasScrolledPast(t)?e:void 0}currentTimelineFragment(){let{pos:e,size:t}=this.currentScrollExtent(),n=e+t/2,r;for(let e of this.sortedFragmentIds){let t=this.cachedFragmentStarts.get(e);if(t!==void 0){if(t<=n)r=e;else break}}return r}sortedVisibleFragmentIds(){let{pos:e,size:t}=this.currentScrollExtent(),n=e+t,r=-1,i=-1;for(let t=0;t<this.sortedFragmentIds.length;t++){let a=this.cachedFragmentStarts.get(this.sortedFragmentIds[t]);a!==void 0&&(a<=e&&(r=t),a<n&&(i=t))}return r<0&&(r=0),i<r?[]:this.sortedFragmentIds.slice(r,i+1)}inCenterBand(e){return!1}buildStyles(){return`
        html, body {
            touch-action: manipulation;
            user-select: ${this.protected?`none`:`auto`};
        }`}mount(t,n){let r=t.document.createElement(`style`);return r.dataset.readium=`true`,r.id=Ea,r.textContent=this.buildStyles(),t.document.head.appendChild(r),n.register(`protect`,e.moduleName,(e,t)=>{this.protected=!0,r.textContent=this.buildStyles(),t(!0)}),n.register(`unprotect`,e.moduleName,(e,t)=>{this.protected=!1,r.textContent=this.buildStyles(),t(!0)}),n.log(`Snapper Mounted`),!0}unmount(e,t){return e.document.getElementById(Ea)?.remove(),this.timelineEntries.clear(),this.cachedFragmentIds=[],this.sortedFragmentIds=[],this.cachedFragmentStarts.clear(),t.log(`Snapper Unmounted`),!0}};Da.moduleName=`snapper`,Da.CENTER_TOLERANCE=.01;var z=Da;function Oa(e){return(e.document.documentElement.dir||e.document.body.dir).toLowerCase()===`rtl`}function ka(e){return(e.getComputedStyle(e.document.documentElement).writingMode||e.getComputedStyle(e.document.body).writingMode)===`vertical-lr`}function Aa(e){let t=e.getComputedStyle(e.document.documentElement).writingMode||e.getComputedStyle(e.document.body).writingMode;return t===`vertical-rl`||t===`vertical-lr`}function ja(e){let t=Aa(e),n=t&&ka(e),r=e.innerWidth,i=e.innerHeight,a=e.document.scrollingElement,o=a.scrollLeft,s=a.scrollTop,c=parseInt(e.getComputedStyle(e.document.documentElement).getPropertyValue(`column-count`)),l=t&&!n?a.scrollWidth-r+o:o,u=s;return{isVertical:t,isVertLR:n,viewportInlineSize:t?i:r,viewportBlockSize:t?r:i,pageInlineSize:t?i:r/(c||1),xDocOffset:l,yDocOffset:u,inlineScrollOffset:t?u:l,blockScrollOffset:t?l:u,inlineStart:e=>t?e.top:e.left,blockStart:e=>t?e.left:e.top,inlineSize:e=>t?e.height:e.width,blockSize:e=>t?e.width:e.height,applyPosition(e,n,r,i,a,o){e.style.position=`absolute`,e.style.zIndex=`2147483646`,t?(e.style.top=`${n*o}px`,e.style.left=`${r*o}px`,e.style.height=`${i*o}px`,e.style.width=`${a*o}px`):(e.style.left=`${n*o}px`,e.style.top=`${r*o}px`,e.style.width=`${i*o}px`,e.style.height=`${a*o}px`)},toRect(e,n,r,i){return t?new DOMRect(n,e,i,r):new DOMRect(e,n,r,i)}}}function Ma(e){return parseInt(e.getComputedStyle(e.document.documentElement).getPropertyValue(`column-count`))}function Na(e){let t=getComputedStyle(e),n=parseFloat(t.paddingTop||`0`),r=parseFloat(t.paddingBottom||`0`);return e.clientHeight-n-r}function Pa(e){let t=Ma(e);if(!t)return!1;let n=e.document.querySelectorAll(`div[id^='readium-virtual-page']`);for(let e of n)e.remove();let r=n.length,i=e.document.scrollingElement.scrollWidth,a=e.visualViewport.width,o=Math.round(i/a*t)%t,s=t===1||o===0?0:t-o;if(s>0)for(let t=0;t<s;t++){let n=e.document.createElement(`div`);n.setAttribute(`id`,`readium-virtual-page-${t}`),n.dataset.readium=`true`,CSS.supports(`break-before`,`column`)?n.style.breakBefore=`column`:(CSS.supports(`break-inside`,`avoid-column`)&&(n.style.breakInside=`avoid-column`),n.style.height=Na(e.document.documentElement)+`px`),n.innerHTML=`&#8203;`,e.document.body.appendChild(n)}return r!==s}function Fa(e){let t=e.document.createElement(`style`);t.appendChild(e.document.createTextNode(`*{}`)),e.document.body.appendChild(t),e.document.body.removeChild(t)}var Ia=()=>typeof window.CSSTransformValue<`u`,La=new Set([`backgroundColor`,`textColor`,`linkColor`,`visitedColor`,`primaryColor`,`secondaryColor`,`selectionBackgroundColor`,`selectionTextColor`,`blendFilter`,`darkenFilter`,`invertFilter`,`invertGaiji`]),Ra=/--(?:USER|RS)__([\w-]+)/g;function za(e,t){let n=e??``,r=t??``,i=new Set;for(let e of n.matchAll(Ra))i.add(e[1]);for(let e of r.matchAll(Ra))i.add(e[1]);for(let e of i)if(!La.has(e))return!0;return!1}function Ba(e){let t={},n=e.document.documentElement.style;for(let r in e.document.documentElement.style)Object.hasOwn(n,r)&&!Number.isNaN(Number.parseInt(r))&&(t[n[r]]=n.getPropertyValue(n[r]));return t}function Va(e,t){let n=Ba(e);Object.keys(n).forEach(n=>{t.hasOwnProperty(n)||Wa(e,n)}),Object.entries(t).forEach(([t,r])=>{n[t]!==r&&Ua(e,t,r)})}function Ha(e,t){return e.document.documentElement.style.getPropertyValue(t)}function Ua(e,t,n){e.document.documentElement.style.setProperty(t,n)}function Wa(e,t){e.document.documentElement.style.removeProperty(t)}function Ga(e){return e<.5?2*e*e:-1+(4-2*e)*e}var Ka=null,qa=null,Ja=0,Ya={r:255,g:255,b:255,a:1},Xa=new Map,Za=()=>{if(!Ka){if(typeof OffscreenCanvas<`u`)Ka=new OffscreenCanvas(5,5),qa=Ka.getContext(`2d`,{willReadFrequently:!0,desynchronized:!0});else{let e=document.createElement(`canvas`);e.width=5,e.height=5,Ka=e,qa=e.getContext(`2d`,{willReadFrequently:!0,desynchronized:!0})}}return qa},Qa=e=>{if(!e)return!0;let t=e.trim().toLowerCase();return t.startsWith(`var(`)||[`transparent`,`currentcolor`,`inherit`,`initial`,`revert`,`unset`,`revert-layer`].includes(t)?!0:[`linear-gradient`,`radial-gradient`,`conic-gradient`,`repeating-linear-gradient`,`repeating-radial-gradient`,`repeating-conic-gradient`].some(e=>t.includes(e))},$a=(e,t)=>{console.warn(`[@readium/helpers] Could not parse color: "${e}". ${t} Falling back to ${JSON.stringify(Ya)} to compute contrast. Please use a CSS color value that can be computed to RGB(A).`)},eo=(e,t=null)=>{let n=t?`${e}|${t}`:e,r=Xa.get(n);if(r!==void 0)return r??Ya;if(Qa(e))return $a(e,`Unsupported color format or special value.`),Xa.set(n,null),Ya;let i=Za();if(!i)return $a(e,`Could not get canvas context.`),Xa.set(n,null),Ya;try{Ja===0&&i.clearRect(0,0,5,5);let r=Ja%5,a=Math.floor(Ja/5);i.clearRect(r,a,1,1),t&&(i.fillStyle=t,i.fillRect(r,a,1,1)),i.fillStyle=e,i.fillRect(r,a,1,1);let o=i.getImageData(r,a,1,1);Ja=(Ja+1)%25;let[s,c,l,u]=o.data;if(u===0)return $a(e,`Fully transparent color.`),Xa.set(n,null),Ya;let d={r:s,g:c,b:l,a:u/255};return Xa.set(n,d),d}catch(t){return $a(e,`Error: ${t instanceof Error?t.message:String(t)}`),Xa.set(n,null),Ya}},to=e=>{let t=e/255;return t<=.03928?t/12.92:((t+.055)/1.055)**2.4},no=e=>{let t=to(e.r),n=to(e.g),r=to(e.b);return .2126*t+.7152*n+.0722*r},ro=(e,t)=>{let n=typeof e==`string`?eo(e):e,r=typeof t==`string`?eo(t):t,i=no(n),a=no(r),o=Math.max(i,a),s=Math.min(i,a);return(o+.05)/(s+.05)},io=(e,t=null)=>{let n=eo(e,t);return ro(n,{r:255,g:255,b:255,a:1})>ro(n,{r:0,g:0,b:0,a:1})},ao=(e,t=null)=>io(e,t)?`white`:`black`,oo=e=>{let t=e.a===void 0?1:e.a;return`rgba(${Math.round(e.r)}, ${Math.round(e.g)}, ${Math.round(e.b)}, ${t})`},so=(e,t)=>({r:Math.min(255,e.r+(255-e.r)*t),g:Math.min(255,e.g+(255-e.g)*t),b:Math.min(255,e.b+(255-e.b)*t),a:e.a??1}),co=(e,t)=>({r:Math.max(0,e.r*(1-t)),g:Math.max(0,e.g*(1-t)),b:Math.max(0,e.b*(1-t)),a:e.a??1}),lo=(e,t=null,n=3)=>{let r=eo(e),i=t?eo(t):{r:255,g:255,b:255,a:1},a=ro(r,i);if(a>=n)return e;let o=no(i)<.5,s={...r,a:r.a??1},c=.1;for(let e=0;e<20&&(s=o?so(s,c):co(s,c),a=ro(s,i),!(a>=n));e++);return oo(s)},uo=()=>typeof navigator>`u`?``:navigator.userAgent||``,fo=()=>typeof navigator>`u`?void 0:navigator.userAgentData||void 0,po=class{constructor(){let e=fo(),t=uo(),n=e=>(typeof e==`string`||typeof e==`number`)&&e?String(e).replace(/_/g,`.`).split(`.`).map(e=>parseInt(e)||0):[],r=(e=``)=>{if(!e)return[];let r=RegExp(`^.*`+e+`[ :\\/]?(\\d+([\\._]\\d+)*).*$`);return r.test(t)?n(t.replace(r,`$1`)):[]};this.OS=(e=>(/(macOS|Mac OS X)/.test(t)?(/\(iP(hone|od touch);/.test(t)&&(e.iOS=r(`CPU (?:iPhone )?OS `)),/\(iPad;/.test(t)?e.iOS=e.iPadOS=r(`CPU (?:iPhone )?OS `):/(macOS|Mac OS X) \d/.test(t)&&(document.ontouchend===void 0?e.macOS=r(`(?:macOS|Mac OS X) `):e.iOS=e.iPadOS=r())):/Windows( NT)? \d/.test(t)?e.Windows=(e=>e[0]!==6||!e[1]?e:e[1]===1?[7]:e[1]===2?[8]:[8,1])(r(`Windows(?: NT)?`)):/Android \d/.test(t)?e.Android=r(`Android`):/CrOS/.test(t)?e.ChromeOS=r():/X11;/.test(t)&&(e.Linux=r()),e))({}),e&&e.getHighEntropyValues([`architecture`,`model`,`platform`,`platformVersion`,`uaFullVersion`]).then(e=>(t=>{let r=e.platform,i=e.platformVersion;if(r&&i){if(/^i(OS|P(hone|od touch))$/.test(r))t.iOS=n(i);else if(/^iPad(OS)?$/.test(r))t.iOS=t.iPadOS=n(i);else if(/^(macOS|(Mac )?OS X|Mac(Intel)?)$/.test(r))document.ontouchend===void 0?t.macOS=n(i):t.iOS=t.iPadOS=n();else if(/^(Microsoft )?Windows$/.test(r))t.Windows=n(i);else if(/^(Google )?Android$/.test(r))t.Android=n(i);else if(/^((Google )?Chrome OS|CrOS)$/.test(r))t.ChromeOS=n(i);else if(/^(Linux|Ubuntu|X11)$/.test(r))t.Linux=n(i);else return;Object.keys(this.OS).forEach(e=>delete this.OS[e]),Object.assign(this.OS,t)}})({})),this.UA=(n=>{let i=!1;if(e&&Array.isArray(e.brands)){let t=e.brands.reduce((e,t)=>(e[t.brand]=[t.version*1],e),{});t[`Google Chrome`]?(i=!0,n.Blink=n.Chromium=t.Chromium||[],n.Chrome=t[`Google Chrome`]):t[`Microsoft Edge`]?(i=!0,n.Blink=n.Chromium=t.Chromium||[],n.Edge=t[`Microsoft Edge`]):t.Opera&&(i=!0,n.Blink=n.Chromium=t.Chromium||[],n.Opera=t.Opera)}return i||(/ Gecko\/\d/.test(t)?(n.Gecko=r(`rv`),/ Waterfox\/\d/.test(t)?n.Waterfox=r(`Waterfox`):/ Firefox\/\d/.test(t)&&(n.Firefox=r(`Firefox`))):/ Edge\/\d/.test(t)?(n.EdgeHTML=r(`Edge`),n.Edge=n.EdgeHTML):/ Chrom(ium|e)\/\d/.test(t)?(n.Blink=n.Chromium=(e=>e[0]?e:r(`Chrome`))(r(`Chromium`)),/ EdgA?\/\d/.test(t)?n.Edge=(e=>e[0]?e:r(`Edg`))(r(`EdgA`)):/ OPR\/\d/.test(t)?n.Opera=r(`OPR`):/ Vivaldi\/\d/.test(t)?n.Vivaldi=r(`Vivaldi`):/ Silk\/\d/.test(t)?n.Silk=r(`Silk`):/ UCBrowser\/\d/.test(t)?n.UCBrowser=r(`UCBrowser`):/ Phoebe\/\d/.test(t)?n.Phoebe=r(`Phoebe`):n.Chrome=(e=>e[0]?e:n.Chromium)(r(`Chrome`))):/ AppleWebKit\/\d/.test(t)?(n.WebKit=r(`AppleWebKit`),/ CriOS \d/.test(t)?n.Chrome=r(`CriOS`):/ FxiOS \d/.test(t)?n.Firefox=r(`FxiOS`):/ EdgiOS\/\d/.test(t)?n.Edge=r(`EdgiOS`):/ Version\/\d/.test(t)&&(n.Safari=r(`Version`))):/ Trident\/\d/.test(t)&&(n.Trident=r(`Trident`),n.InternetExplorer=(e=>e[0]?e:r(`MSIE`))(r(`rv`)))),/[\[; ]FB(AN|_IAB)\//.test(t)&&(n.Facebook=r(`FBAV`)),/ Line\/\d/.test(t)&&(n.LINE=r(`Line`)),n})({}),this.Env={get:()=>[this.OS,this.UA].reduce((e,t)=>{for(let n in t)t[n]&&e.push(n);return e},[])}}},mo=class extends po{get iOSRequest(){let e=fo(),t=uo();if(this.OS.iOS&&!this.OS.iPadOS)return`mobile`;if(this.OS.iPadOS)return/\(iPad;/.test(t)||e&&/^iPad(OS)?$/.test(e.platform)?`mobile`:`desktop`}},B=new po,V=new mo,ho=`ADDRESS.ARTICLE.ASIDE.BLOCKQUOTE.BR.DETAILS.DIALOG.DD.DIV.DL.DT.FIELDSET.FIGCAPTION.FIGURE.FOOTER.FORM.H1.H2.H3.H4.H5.H6.HEADER.HGROUP.HR.LI.MAIN.NAV.OL.P.PRE.SECTION.TABLE.UL.TR.TH.TD.COLGROUP.COL.CAPTION.THEAD.TBODY.TFOOT`.split(`.`),go=/[\t-\r -#%-\*,-\/:;\?@\[-\]_\{\}\x85\xA0\xA1\xA7\xAB\xB6\xB7\xBB\xBF\u037E\u0387\u055A-\u055F\u0589\u058A\u05BE\u05C0\u05C3\u05C6\u05F3\u05F4\u0609\u060A\u060C\u060D\u061B\u061E\u061F\u066A-\u066D\u06D4\u0700-\u070D\u07F7-\u07F9\u0830-\u083E\u085E\u0964\u0965\u0970\u0AF0\u0DF4\u0E4F\u0E5A\u0E5B\u0F04-\u0F12\u0F14\u0F3A-\u0F3D\u0F85\u0FD0-\u0FD4\u0FD9\u0FDA\u104A-\u104F\u10FB\u1360-\u1368\u1400\u166D\u166E\u1680\u169B\u169C\u16EB-\u16ED\u1735\u1736\u17D4-\u17D6\u17D8-\u17DA\u1800-\u180A\u1944\u1945\u1A1E\u1A1F\u1AA0-\u1AA6\u1AA8-\u1AAD\u1B5A-\u1B60\u1BFC-\u1BFF\u1C3B-\u1C3F\u1C7E\u1C7F\u1CC0-\u1CC7\u1CD3\u2000-\u200A\u2010-\u2029\u202F-\u2043\u2045-\u2051\u2053-\u205F\u207D\u207E\u208D\u208E\u2308-\u230B\u2329\u232A\u2768-\u2775\u27C5\u27C6\u27E6-\u27EF\u2983-\u2998\u29D8-\u29DB\u29FC\u29FD\u2CF9-\u2CFC\u2CFE\u2CFF\u2D70\u2E00-\u2E2E\u2E30-\u2E44\u3000-\u3003\u3008-\u3011\u3014-\u301F\u3030\u303D\u30A0\u30FB\uA4FE\uA4FF\uA60D-\uA60F\uA673\uA67E\uA6F2-\uA6F7\uA874-\uA877\uA8CE\uA8CF\uA8F8-\uA8FA\uA8FC\uA92E\uA92F\uA95F\uA9C1-\uA9CD\uA9DE\uA9DF\uAA5C-\uAA5F\uAADE\uAADF\uAAF0\uAAF1\uABEB\uFD3E\uFD3F\uFE10-\uFE19\uFE30-\uFE52\uFE54-\uFE61\uFE63\uFE68\uFE6A\uFE6B\uFF01-\uFF03\uFF05-\uFF0A\uFF0C-\uFF0F\uFF1A\uFF1B\uFF1F\uFF20\uFF3B-\uFF3D\uFF3F\uFF5B\uFF5D\uFF5F-\uFF65]|\uD800[\uDD00-\uDD02\uDF9F\uDFD0]|\uD801\uDD6F|\uD802[\uDC57\uDD1F\uDD3F\uDE50-\uDE58\uDE7F\uDEF0-\uDEF6\uDF39-\uDF3F\uDF99-\uDF9C]|\uD804[\uDC47-\uDC4D\uDCBB\uDCBC\uDCBE-\uDCC1\uDD40-\uDD43\uDD74\uDD75\uDDC5-\uDDC9\uDDCD\uDDDB\uDDDD-\uDDDF\uDE38-\uDE3D\uDEA9]|\uD805[\uDC4B-\uDC4F\uDC5B\uDC5D\uDCC6\uDDC1-\uDDD7\uDE41-\uDE43\uDE60-\uDE6C\uDF3C-\uDF3E]|\uD807[\uDC41-\uDC45\uDC70\uDC71]|\uD809[\uDC70-\uDC74]|\uD81A[\uDE6E\uDE6F\uDEF5\uDF37-\uDF3B\uDF44]|\uD82F\uDC9F|\uD836[\uDE87-\uDE8B]|\uD83A[\uDD5E\uDD5F]/u,_o=(e,t,n)=>{let r=[],i=t.createRange();for(i.selectNodeContents(n??t);!i.collapsed&&r.length<2;){let n;if(e.prefix){let r=Ao(e.prefix,i);if(r==null)break;bo(i,r.startContainer,r.startOffset);let a=t.createRange();if(a.setStart(r.endContainer,r.endOffset),a.setEnd(i.endContainer,i.endOffset),xo(a),a.collapsed||(n=Ao(e.textStart,a),n==null))break;if(n.compareBoundaryPoints(Range.START_TO_START,a)!==0)continue}else{if(n=Ao(e.textStart,i),n==null)break;bo(i,n.startContainer,n.startOffset)}if(e.textEnd){let a=t.createRange();a.setStart(n.endContainer,n.endOffset),a.setEnd(i.endContainer,i.endOffset);let o=!1;for(;!a.collapsed&&r.length<2;){let s=Ao(e.textEnd,a);if(s==null)break;if(bo(a,s.startContainer,s.startOffset),n.setEnd(s.endContainer,s.endOffset),e.suffix){let a=yo(e.suffix,n,i,t);if(a===vo.NO_SUFFIX_MATCH)break;if(a===vo.SUFFIX_MATCH){o=!0,r.push(n.cloneRange());continue}if(a===vo.MISPLACED_SUFFIX)continue}else o=!0,r.push(n.cloneRange())}if(!o)break}else if(e.suffix){let a=yo(e.suffix,n,i,t);if(a===vo.NO_SUFFIX_MATCH)break;if(a===vo.SUFFIX_MATCH){r.push(n.cloneRange()),bo(i,i.startContainer,i.startOffset);continue}if(a===vo.MISPLACED_SUFFIX)continue}else r.push(n.cloneRange())}return r},vo={NO_SUFFIX_MATCH:0,SUFFIX_MATCH:1,MISPLACED_SUFFIX:2},yo=(e,t,n,r)=>{let i=r.createRange();i.setStart(t.endContainer,t.endOffset),i.setEnd(n.endContainer,n.endOffset),xo(i);let a=Ao(e,i);return a==null?vo.NO_SUFFIX_MATCH:a.compareBoundaryPoints(Range.START_TO_START,i)===0?vo.SUFFIX_MATCH:vo.MISPLACED_SUFFIX},bo=(e,t,n)=>{try{e.setStart(t,n+1)}catch{e.setStartAfter(t)}},xo=e=>{let t=So(e),n=t.nextNode();for(;!e.collapsed&&n!=null;){if(n!==e.startContainer&&e.setStart(n,0),n.textContent.length>e.startOffset&&!n.textContent[e.startOffset].match(/\s/))return;try{e.setStart(n,e.startOffset+1)}catch{n=t.nextNode(),n==null?e.collapse():e.setStart(n,0)}}},So=e=>(e.commonAncestorContainer.ownerDocument??e.commonAncestorContainer).createTreeWalker(e.commonAncestorContainer,NodeFilter.SHOW_TEXT|NodeFilter.SHOW_ELEMENT,{acceptNode:t=>Eo(t,e)}),Co=e=>{if(e.hidden===`until-found`)return!0;let t=e.attributes;return!!(t&&t.hidden&&t.hidden.value===`until-found`)},wo=e=>{let t=e;for(;t!=null&&!(t instanceof HTMLElement);)t=t.parentNode;let n=t?.ownerDocument?.defaultView;if(t!=null&&n!=null){if(Co(t))return!0;let e=n.getComputedStyle(t);if(e.visibility===`hidden`||e.display===`none`||parseInt(e.height,10)===0&&e.overflowY!=`visible`||parseInt(e.width,10)===0&&e.overflowX!=`visible`||parseInt(e.opacity,10)===0)return!1}return!0},To=(e,t)=>t!=null&&!t.intersectsNode(e)?NodeFilter.FILTER_REJECT:wo(e)?NodeFilter.FILTER_ACCEPT:NodeFilter.FILTER_REJECT,Eo=(e,t)=>t!=null&&!t.intersectsNode(e)||!wo(e)?NodeFilter.FILTER_REJECT:e.nodeType===Node.TEXT_NODE?NodeFilter.FILTER_ACCEPT:NodeFilter.FILTER_SKIP,Do=(e,t)=>{let n=[],r=[],i=Array.from(ko(e,e=>To(e,t)));for(let e of i)e.nodeType===Node.TEXT_NODE?r.push(e):e instanceof HTMLElement&&ho.includes(e.tagName.toUpperCase())&&r.length>0&&(n.push(r),r=[]);return r.length>0&&n.push(r),n},Oo=(e,t,n)=>{let r=``;return r=e.length===1?e[0].textContent.substring(t,n):e[0].textContent.substring(t)+e.slice(1,-1).reduce((e,t)=>e+t.textContent,``)+e.slice(-1)[0].textContent.substring(0,n),r.replace(/[\t\n\r ]+/g,` `)};function*ko(e,t){let n=(e.ownerDocument??e).createTreeWalker(e,NodeFilter.SHOW_ELEMENT|NodeFilter.SHOW_TEXT,{acceptNode:t}),r=new Set;for(;Io(n,r)!==null;)yield n.currentNode}var Ao=(e,t)=>{let n=Do(t.commonAncestorContainer,t),r=Fo(t.commonAncestorContainer.ownerDocument??void 0);for(let i of n){let n=jo(e,t,i,r);if(n!==void 0)return n}},jo=(e,t,n,r)=>{if(!e||!t||!(n||[]).length)return;let i=n[0]===t.startContainer?t.startOffset:0,a=Po(Oo(n,i,void 0)),o=Po(e),s=0,c,l;for(;s<a.length;){let e=a.indexOf(o,s);if(e===-1)return;if(No(a,e,o.length,r)){let t=Po(n[0].data.slice(0,i)).length;c=Mo(t+e,n,!1),l=Mo(t+e+o.length,n,!0)}if(c!=null&&l!=null){let e=new Range;if(e.setStart(c.node,c.offset),e.setEnd(l.node,l.offset),t.compareBoundaryPoints(Range.START_TO_START,e)<=0&&t.compareBoundaryPoints(Range.END_TO_END,e)>=0)return e}s=e+1}},Mo=(e,t,n)=>{let r=0,i;for(let a=0;a<t.length;a++){let o=t[a];i||=Po(o.data);let s=r+i.length;if(n&&(s+=1),s>e){let t=e-r,a=Math.min(e-r,o.data.length),s=n?i.substring(0,t):i.substring(t),c=Po(n?o.data.substring(0,a):o.data.substring(a)),l=(n?-1:1)*(s.length>c.length?-1:1);for(;a>=0&&a<=o.data.length;){if(c.length===s.length)return{node:o,offset:a};a+=l,c=Po(n?o.data.substring(0,a):o.data.substring(a))}}if(r+=i.length,a+1<t.length){let e=Po(t[a+1].data);i.slice(-1)===` `&&e.slice(0,1)===` `&&--r,i=e}}},No=(e,t,n,r)=>{if(t<0||t>=e.length||n<=0||t+n>e.length)return!1;if(r){let i=r.segment(e),a=i.containing(t);if(!a||a.isWordLike&&a.index!=t)return!1;let o=t+n,s=i.containing(o);if(s&&s.isWordLike&&s.index!=o)return!1}else if(e[t].match(go)&&(++t,--n,!n)||e[t+n-1].match(go)&&(--n,!n)||t!==0&&!e[t-1].match(go)||t+n!==e.length&&!e[t+n].match(go))return!1;return!0},Po=e=>(e||``).normalize(`NFKD`).replace(/\s+/g,` `).replace(/[\u0300-\u036f]/g,``).toLowerCase(),Fo=e=>{if(Intl.Segmenter){let t=e?.documentElement?.lang||e?.defaultView?.navigator?.language||void 0;return new Intl.Segmenter(t,{granularity:`word`})}},Io=(e,t)=>{if(!t.has(e.currentNode)){let t=e.firstChild();if(t!==null)return t}let n=e.nextSibling();if(n!==null)return n;let r=e.parentNode();return r!==null&&t.add(r),r};function Lo(e){return e.split(``).reverse().join(``)}function Ro(e,t,n){let r=Lo(t);return n.map(n=>{let i=Math.max(0,n.end-t.length-n.errors);return{start:Vo(Lo(e.slice(i,n.end)),r,n.errors).reduce((e,t)=>n.end-t.end<e?n.end-t.end:e,n.end),end:n.end,errors:n.errors}})}function zo(e){return(e|-e)>>31&1}function Bo(e,t,n,r){let i=e.P[n],a=e.M[n],o=r>>>31,s=t[n]|o,c=s|a,l=(s&i)+i^i|s,u=a|~(l|i),d=i&l,f=zo(u&e.lastRowMask[n])-zo(d&e.lastRowMask[n]);return u<<=1,d<<=1,d|=o,u|=zo(r)-o,i=d|~(c|u),a=u&c,e.P[n]=i,e.M[n]=a,f}function Vo(e,t,n){if(t.length===0)return[];n=Math.min(n,t.length);let r=[],i=Math.ceil(t.length/32)-1,a={P:new Uint32Array(i+1),M:new Uint32Array(i+1),lastRowMask:new Uint32Array(i+1)};a.lastRowMask.fill(1<<31),a.lastRowMask[i]=1<<(t.length-1)%32;let o=new Uint32Array(i+1),s=new Map,c=[];for(let e=0;e<256;e++)c.push(o);for(let e=0;e<t.length;e+=1){let n=t.charCodeAt(e);if(s.has(n))continue;let r=new Uint32Array(i+1);s.set(n,r),n<c.length&&(c[n]=r);for(let e=0;e<=i;e+=1){r[e]=0;for(let i=0;i<32;i+=1){let a=e*32+i;a>=t.length||t.charCodeAt(a)===n&&(r[e]|=1<<i)}}}let l=Math.max(0,Math.ceil(n/32)-1),u=new Uint32Array(i+1);for(let e=0;e<=l;e+=1)u[e]=(e+1)*32;u[i]=t.length;for(let e=0;e<=l;e+=1)a.P[e]=-1,a.M[e]=0;for(let d=0;d<e.length;d+=1){let f=e.charCodeAt(d),p;f<c.length?p=c[f]:(p=s.get(f),typeof p>`u`&&(p=o));let m=0;for(let e=0;e<=l;e+=1)m=Bo(a,p,e,m),u[e]+=m;if(u[l]-m<=n&&l<i&&(p[l+1]&1||m<0)){l+=1,a.P[l]=-1,a.M[l]=0;let e;if(l===i){let n=t.length%32;e=n===0?32:n}else e=32;u[l]=u[l-1]+e-m+Bo(a,p,l,m)}else for(;l>0&&u[l]>=n+32;)--l;l===i&&u[l]<=n&&(u[l]<n&&r.splice(0,r.length),r.push({start:-1,end:d+1,errors:u[l]}),n=u[l])}return r}function Ho(e,t,n){return Ro(e,t,Vo(e,t,n))}function Uo(e,t,n){let r=0,i=[];for(;r!==-1;)r=e.indexOf(t,r),r!==-1&&(i.push({start:r,end:r+t.length,errors:0}),r+=1);return i.length>0?i:Ho(e,t,n)}function Wo(e,t){return t.length===0||e.length===0?0:1-Uo(e,t,t.length)[0].errors/t.length}function Go(e,t,n={}){if(t.length===0)return null;let r=Uo(e,t,Math.min(256,t.length/2));if(r.length===0)return null;let i=r=>{let i=1-r.errors/t.length,a=n.prefix?Wo(e.slice(Math.max(0,r.start-n.prefix.length),r.start),n.prefix):1,o=n.suffix?Wo(e.slice(r.end,r.end+n.suffix.length),n.suffix):1,s=1;return typeof n.hint==`number`&&(s=1-Math.abs(r.start-n.hint)/e.length),(50*i+20*a+20*o+2*s)/92},a=r.map(e=>({start:e.start,end:e.end,score:i(e)}));return a.sort((e,t)=>t.score-e.score),a[0]}function Ko(e,t,n){let r=n===1?t:t-1;if(e.charAt(r).trim()!==``)return t;let i,a;if(n===2?(i=e.substring(0,t),a=i.trimEnd()):(i=e.substring(t),a=i.trimStart()),!a.length)return-1;let o=i.length-a.length;return n===2?t-o:t+o}function qo(e,t){let n=e.commonAncestorContainer.ownerDocument.createNodeIterator(e.commonAncestorContainer,NodeFilter.SHOW_TEXT),r=t===1?e.startContainer:e.endContainer,i=t===1?e.endContainer:e.startContainer,a=n.nextNode();for(;a&&a!==r;)a=n.nextNode();t===2&&(a=n.previousNode());let o=-1,s=()=>{if(a=t===1?n.nextNode():n.previousNode(),a){let e=a.textContent;o=Ko(e,t===1?0:e.length,t)}};for(;a&&o===-1&&a!==i;)s();if(a&&o>=0)return{node:a,offset:o};throw RangeError(`No text nodes with non-whitespace text found in range`)}function Jo(e){if(!e.toString().trim().length)throw RangeError(`Range contains no non-whitespace text`);if(e.startContainer.nodeType!==Node.TEXT_NODE)throw RangeError(`Range startContainer is not a text node`);if(e.endContainer.nodeType!==Node.TEXT_NODE)throw RangeError(`Range endContainer is not a text node`);let t=e.cloneRange(),n=!1,r=!1,i={start:Ko(e.startContainer.textContent,e.startOffset,1),end:Ko(e.endContainer.textContent,e.endOffset,2)};if(i.start>=0&&(t.setStart(e.startContainer,i.start),n=!0),i.end>0&&(t.setEnd(e.endContainer,i.end),r=!0),n&&r)return t;if(!n){let{node:e,offset:n}=qo(t,1);e&&n>=0&&t.setStart(e,n)}if(!r){let{node:e,offset:n}=qo(t,2);e&&n>0&&t.setEnd(e,n)}return t}function Yo(e){switch(e.nodeType){case Node.ELEMENT_NODE:case Node.TEXT_NODE:return e.textContent?.length??0;default:return 0}}function Xo(e){let t=e.previousSibling,n=0;for(;t;)n+=Yo(t),t=t.previousSibling;return n}function Zo(e,...t){let n=t.shift(),r=e.ownerDocument.createNodeIterator(e,NodeFilter.SHOW_TEXT),i=[],a=r.nextNode(),o,s=0;for(;n!==void 0&&a;)o=a,s+o.data.length>n?(i.push({node:o,offset:n-s}),n=t.shift()):(a=r.nextNode(),s+=o.data.length);for(;n!==void 0&&o&&s===n;)i.push({node:o,offset:o.data.length}),n=t.shift();if(n!==void 0)throw RangeError(`Offset exceeds text length`);return i}var Qo=class e{constructor(e,t){if(t<0)throw Error(`Offset is invalid`);this.element=e,this.offset=t}relativeTo(t){if(!t.contains(this.element))throw Error(`Parent is not an ancestor of current element`);let n=this.element,r=this.offset;for(;n!==t;)r+=Xo(n),n=n.parentElement;return new e(n,r)}resolve(e={}){try{return Zo(this.element,this.offset)[0]}catch(t){if(this.offset===0&&e.direction!==void 0){let n=document.createTreeWalker(this.element.getRootNode(),NodeFilter.SHOW_TEXT);n.currentNode=this.element;let r=e.direction===1,i=r?n.nextNode():n.previousNode();if(!i)throw t;return{node:i,offset:r?0:i.data.length}}throw t}}static fromCharOffset(t,n){switch(t.nodeType){case Node.TEXT_NODE:return e.fromPoint(t,n);case Node.ELEMENT_NODE:return new e(t,n);default:throw Error(`Node is not an element or text node`)}}static fromPoint(t,n){switch(t.nodeType){case Node.TEXT_NODE:{if(n<0||n>t.data.length)throw Error(`Text node offset is out of range`);if(!t.parentElement)throw Error(`Text node has no parent`);let r=Xo(t)+n;return new e(t.parentElement,r)}case Node.ELEMENT_NODE:{if(n<0||n>t.childNodes.length)throw Error(`Child node offset is out of range`);let r=0;for(let e=0;e<n;e++)r+=Yo(t.childNodes[e]);return new e(t,r)}default:throw Error(`Point is not in an element or text node`)}}},$o=class e{constructor(e,t){this.start=e,this.end=t}relativeTo(t){return new e(this.start.relativeTo(t),this.end.relativeTo(t))}toRange(){let e,t;this.start.element===this.end.element&&this.start.offset<=this.end.offset?[e,t]=Zo(this.start.element,this.start.offset,this.end.offset):(e=this.start.resolve({direction:1}),t=this.end.resolve({direction:2}));let n=new Range;return n.setStart(e.node,e.offset),n.setEnd(t.node,t.offset),n}static fromRange(t){let n=Qo.fromPoint(t.startContainer,t.startOffset),r=Qo.fromPoint(t.endContainer,t.endOffset);return new e(n,r)}static fromOffsets(t,n,r){return new e(new Qo(t,n),new Qo(t,r))}static trimmedRange(t){return Jo(e.fromRange(t).toRange())}},es=class e{constructor(e,t,n){this.root=e,this.start=t,this.end=n}static fromRange(t,n){let r=$o.fromRange(n).relativeTo(t);return new e(t,r.start.offset,r.end.offset)}static fromSelector(t,n){return new e(t,n.start,n.end)}toSelector(){return{type:`TextPositionSelector`,start:this.start,end:this.end}}toRange(){return $o.fromOffsets(this.root,this.start,this.end).toRange()}},ts=class e{constructor(e,t,n={}){this.root=e,this.exact=t,this.context=n}static fromRange(t,n){let r=t.textContent,i=$o.fromRange(n).relativeTo(t),a=i.start.offset,o=i.end.offset;return new e(t,r.slice(a,o),{prefix:r.slice(Math.max(0,a-32),a),suffix:r.slice(o,Math.min(r.length,o+32))})}static fromSelector(t,n){let{prefix:r,suffix:i}=n;return new e(t,n.exact,{prefix:r,suffix:i})}toSelector(){return{type:`TextQuoteSelector`,exact:this.exact,prefix:this.context.prefix,suffix:this.context.suffix}}toRange(e={}){return this.toPositionAnchor(e).toRange()}toPositionAnchor(e={}){let t=this.root.textContent,n=Go(t,this.exact,{...this.context,hint:e.hint});if(!n)throw Error(`Quote not found`);return new es(this.root,n.start,n.end)}};function ns(e){let t=e.tagName.toUpperCase();return t===`IMG`||t===`VIDEO`||t===`AUDIO`||t===`IFRAME`||t===`OBJECT`||t===`EMBED`||t===`CANVAS`}function rs(e,t){let n=t&&Nt(t),r=null;if(n)try{r=e.querySelector(n)}catch(e){console.warn(`Invalid cssSelector: ${n}`,e)}return r??e.body??e.documentElement}function is(e,t){let n;try{n=e.querySelector(t.cssSelector)}catch(e){return console.error(`Invalid domRange cssSelector: ${t.cssSelector}`,e),null}if(!n)return console.error(`Can't resolve domRange cssSelector: ${t.cssSelector}`),null;let r=0;for(let e of n.childNodes)if(e.nodeType===Node.TEXT_NODE){if(r===t.textNodeIndex)return{node:e,offset:t.charOffset};r++}return console.error(`Can't resolve domRange textNodeIndex ${t.textNodeIndex} for selector: ${t.cssSelector}`),null}function as(e,t){try{let n=t.locations,r=t.text;if(n){let t=Ft(n);if(t){let n=is(e,t.start),r=t.end?is(e,t.end):n;if(n&&r)try{let t=e.createRange();return n.offset===void 0?t.setStartBefore(n.node):t.setStart(n.node,n.offset),r.offset===void 0?t.setEndBefore(r.node):t.setEnd(r.node,r.offset),t}catch(e){console.warn(`Invalid domRange, falling back:`,e)}}}if(n){let t=It(n);if(t){let r=_o(t,e,rs(e,n));if(r.length>0)return r[0]}}if(r&&r.highlight){let t=new ts(rs(e,n),r.highlight,{prefix:r.before,suffix:r.after});try{return t.toRange()}catch{return console.warn(`Quote not found:`,t),null}}if(n){let t=null;if(!t&&Nt(n)&&(t=e.querySelector(Nt(n))),!t&&n.fragments){for(let r of n.fragments)if(t=e.getElementById(r),t)break}if(t){let n=e.createRange();return t.childNodes.length===0||ns(t)?(n.selectNode(t),n):(n.setStartBefore(t),n.setEndAfter(t),n)}}}catch(e){console.error(e)}return null}function H(e){let t=e.getSelection();t&&t.removeAllRanges()}var os=[`a`,`area`,`audio`,`button`,`canvas`,`details`,`input`,`label`,`option`,`select`,`submit`,`textarea`,`video`],ss=[`dialog`,`radiogroup`,`radio`,`menu`,`menuitem`];function cs(e){return ls(e)?null:us(e)?e:e.parentElement?cs(e.parentElement):null}function ls(e){return!e||e.closest(`[inert]`)!==null||e.hasAttribute(`disabled`)}function us(e){return e?e.role&&ss.includes(e.role)?!0:e.tagName.toLowerCase()===`iframe`?!1:e.tabIndex>=0||os.includes(e.nodeName.toLowerCase())||e.hasAttribute(`contenteditable`)&&e.getAttribute(`contenteditable`)?.toLowerCase()!==`false`:!1}function ds(e,t){let n=fs(e,e.document.body,t),r=e._readium_cssSelectorGenerator.getCssSelector(n,{selectors:[`tag`,`id`,`class`,`nthchild`,`nthoftype`,`attribute`]});return new j({href:`#`,type:`application/xhtml+xml`,locations:new k({otherLocations:new Map([[`cssSelector`,r]])}),text:new A({highlight:n.textContent||void 0})})}function fs(e,t,n){for(var r=0;r<t.children.length;r++){let i=t.children[r];if(!hs(i)&&ps(e,i,n))return ms(e,i)?i:fs(e,i,n)}return t}function ps(e,t,n){if(t===document.body||t===document.documentElement)return!0;if(!document||!document.documentElement||!document.body)return!1;let r=t.getBoundingClientRect();return n?r.bottom>0&&r.top<e.innerHeight:r.right>0&&r.left<e.innerWidth}function ms(e,t){let n=t.getBoundingClientRect();return n.top>=0&&n.left>=0&&n.bottom<=e.innerHeight&&n.right<=e.innerWidth}function hs(e){let t=getComputedStyle(e);if(t){let e=t.getPropertyValue(`display`);if(e!=`block`&&e!=`list-item`||t.getPropertyValue(`opacity`)===`0`)return!0}return!1}var gs={maxVelocity:200,minVariance:.01,historySize:20,minDirectionChanges:.2,maxConsistentScrolls:15},_s={maxVelocity:200,minVariance:1e-5,historySize:100,minDirectionChanges:.1,maxConsistentScrolls:20},vs={maxSelectionsPerSecond:500,minVariance:50,historySize:20},ys={enabled:!0,maxSelectionPercent:.1,minThreshold:100,absoluteMaxChars:5e3,historySize:20},bs=class{constructor(e={}){this.history=[],this.consistentScrollCount=0,this.options={...gs,...e}}analyze(e,t,n){if(n<=0)return!1;let r=Math.abs(t)/n,i=Date.now();if(this.history.push({timestamp:i,direction:e,velocity:r,distance:Math.abs(t)}),this.history=this.history.filter(e=>i-e.timestamp<2e3).slice(-(this.options.historySize||20)),this.history.length<3)return!1;if(r>this.options.maxVelocity)return this.resetAfterDetection(),!0;let a=this.history.map(e=>e.velocity),o=this.history.map(e=>e.distance),s=a.reduce((e,t)=>e+t,0)/a.length,c=o.reduce((e,t)=>e+t,0)/o.length,l=a.reduce((e,t)=>e+(t-s)**2,0)/a.length,u=o.reduce((e,t)=>e+(t-c)**2,0)/o.length;if(l<this.options.minVariance&&u<c*.1){if(this.consistentScrollCount++,this.consistentScrollCount>=(this.options.maxConsistentScrolls||10))return this.resetAfterDetection(),!0}else this.consistentScrollCount=Math.max(0,this.consistentScrollCount-1);let d=0,f=this.history[0].direction;for(let e=1;e<this.history.length;e++)this.history[e].direction!==f&&(d++,f=this.history[e].direction);return d/this.history.length>(this.options.minDirectionChanges||.3)&&(this.resetAfterDetection(),!0)}resetAfterDetection(){this.history=this.history.slice(-3),this.consistentScrollCount=0}clear(){this.history=[],this.consistentScrollCount=0}},xs=`readium-column-snapper-style`,Ss=200,Cs=class e extends z{constructor(){super(...arguments),this.isSnapProtectionEnabled=!1,this.patternAnalyzer=null,this.lastTurnTime=0,this.rtl=!1,this.shakeTimeout=0,this.snappingCancelled=!1,this.alreadyScrollLeft=0,this.overscroll=0,this.cachedScrollWidth=0,this.touchState=0,this.startingX=void 0,this.endingX=void 0,this.onTouchStarter=this.onTouchStart.bind(this),this.onTouchEnder=this.onTouchEnd.bind(this),this.onWidthChanger=this.onWidthChange.bind(this),this.onTouchMover=this.onTouchMove.bind(this)}doc(){return this.wnd.document.scrollingElement}scrollOffset(){let e=this.doc().scrollLeft;return e===0?this.alreadyScrollLeft:e}snapOffset(e){let t=e+(this.rtl?-1:1);return t-t%this.wnd.innerWidth}snapNormOffset(e){let t=e+1;return t-t%this.wnd.innerWidth}normScroll(){let e=this.doc().scrollLeft||this.alreadyScrollLeft;return this.rtl?Math.abs(e):Math.max(0,this.wnd.scrollX>0?this.wnd.scrollX:e)}hasScrolledPast(e){let t=e.getBoundingClientRect();return this.rtl?t.left>=this.wnd.innerWidth:t.right<=0}currentTimelineFragment(){if(this.timelineEntries.size===0)return;let e=this.wnd.innerWidth,t;for(let n of this.sortedFragmentIds){let r=this.timelineEntries.get(n).getBoundingClientRect();if(this.rtl?r.right>0:r.left<e)t=n;else break}return t}sortedVisibleFragmentIds(){let e=this.wnd.innerWidth;return this.sortedFragmentIds.filter(t=>{let n=this.timelineEntries.get(t).getBoundingClientRect();return this.rtl?n.left<e&&n.right>0:n.right>0&&n.left<e})}reportProgress(e){let t=this.cachedScrollWidth,n=this.wnd.innerWidth,r=this.normScroll(),i=Math.max(1,t-n),a=Math.max(0,Math.min(1,r/i)),o=Math.max(0,Math.min(1,(r+n)/t));this.comms.send(`progress`,{start:a,end:o,fragmentId:e===void 0?this.currentTimelineFragment():e,visibleFragmentIds:this.sortedVisibleFragmentIds()})}shake(){if(this.overscroll!==0||this.shakeTimeout!==0)return;let e=this.doc(),t=this.normScroll()<5,n=this.rtl?t?`readium-bounce-r`:`readium-bounce-l`:`readium-bounce-r`;e.classList.add(n);let r=this.scrollOffset();this.shakeTimeout=this.wnd.setTimeout(()=>{e.classList.remove(n),this.shakeTimeout=0,this.doc().scrollLeft=r},150)}takeOverSnap(){this.snappingCancelled=!0,this.clearTouches();let e=this.doc();this.overscroll=e.style.transform?.length>12?parseFloat(e.style.transform.slice(12).split(`px`)[0]):0}snapCurrentOffset(e=!1,t=!1){let n=this.doc(),r=Ma(this.wnd),i=this.cachedScrollWidth-this.wnd.innerWidth,a=Math.min(Math.max(0,this.normScroll()),i),o=this.dragOffset(),s=this.rtl?-o:o,c=this.wnd.innerWidth/3*(s>0?2:1),l=Math.min(i,Math.max(0,this.snapNormOffset(a+c))),u=this.rtl?-l:l,d=this.rtl?-a:a,f=u>d?`right`:`left`;if(this.checkSuspiciousSnap(f,Math.abs(u-d)),e&&u!==d){this.snappingCancelled=!1;let e=(e,t,n,r)=>n>r?t:e+(t-e)*Ga(n/r),i=Ss*r,a,o=r=>{if(this.snappingCancelled)return;a||=r;let s=r-a,c=e(this.overscroll,0,s,i),l=e(d,u,s,i);n.scrollLeft=l,this.overscroll!==0&&(Ia()?n.attributeStyleMap.set(`transform`,new CSSTransformValue([new CSSTranslate(CSS.px(-c),CSS.px(0),CSS.px(0))])):n.style.transform=`translate3d(${-c}px, 0px, 0px)`),s<i?this.wnd.requestAnimationFrame(o):(this.clearTouches(),n.style.removeProperty(`transform`),n.scrollLeft=u,t||this.reportProgress())};this.wnd.requestAnimationFrame(o)}else n.style.removeProperty(`transform`),this.wnd.requestAnimationFrame(()=>{n.scrollLeft=u,this.clearTouches(),t||this.reportProgress()})}dragOffset(){return(this.startingX??0)-(this.endingX??0)}clearTouches(){this.startingX=void 0,this.endingX=void 0,this.overscroll=0}onTouchStart(e){switch(e.stopPropagation(),this.takeOverSnap(),e.touches.length){case 1:break;case 2:this.onTouchEnd(e);return;default:this.onTouchEnd(e),this.comms.send(`tap_more`,e.touches.length);return}this.startingX=e.touches[0].clientX,this.alreadyScrollLeft=this.doc().scrollLeft,this.touchState=1}onTouchEnd(e){if(this.touchState===2){let e=this.dragOffset(),t=this.normScroll(),n=this.cachedScrollWidth-this.wnd.innerWidth,r=this.rtl?-e:e;this.cachedScrollWidth<=this.wnd.innerWidth?(this.reportProgress(),r>5&&this.comms.send(`no_more`,void 0),r<-5&&this.comms.send(`no_less`,void 0)):t<5&&r<5?(this.alreadyScrollLeft=0,this.comms.send(`no_less`,void 0)):n-t<5&&r>5&&(this.alreadyScrollLeft=this.rtl?-n:n,this.comms.send(`no_more`,void 0)),this.snapCurrentOffset(!0),this.comms.send(`swipe`,e)}this.touchState=0}onWidthChange(){this.cachedScrollWidth=this.doc().scrollWidth,this.comms.ready&&this.snapCurrentOffset()}onTouchMove(e){if(this.touchState===0)return;this.touchState===1&&(this.touchState=2,H(this.wnd)),this.endingX=e.touches[0].clientX;let t=this.dragOffset(),n=this.alreadyScrollLeft+t,r=this.rtl?-(this.cachedScrollWidth-this.wnd.innerWidth):0,i=this.rtl?0:this.cachedScrollWidth-this.wnd.innerWidth;n<r||n>i?(this.overscroll=n,Ia()?this.doc().attributeStyleMap.set(`transform`,new CSSTransformValue([new CSSTranslate(CSS.px(-n),CSS.px(0),CSS.px(0))])):this.doc().style.transform=`translate3d(${-n}px, 0px, 0px)`):(this.overscroll=0,this.doc().style.removeProperty(`transform`),this.doc().scrollLeft=n)}enableSnapProtection(){this.patternAnalyzer||(this.patternAnalyzer=new bs({maxVelocity:this.wnd.innerWidth,minVariance:.1,historySize:5,maxConsistentScrolls:3,minDirectionChanges:.3}),this.isSnapProtectionEnabled=!0,this.comms?.log(`Snap protection enabled`))}checkSuspiciousSnap(e,t){if(!this.isSnapProtectionEnabled||!this.patternAnalyzer)return;let n=Date.now(),r=n-(this.lastTurnTime||n);this.lastTurnTime=n,this.patternAnalyzer.analyze(e,t,r)&&this.comms?.send(`content_protection`,{type:`suspicious_snapping`,timestamp:Date.now(),event:null})}mount(t,n){if(this.wnd=t,this.comms=n,this.rtl=Oa(t),!super.mount(t,n))return!1;t.navigator.epubReadingSystem&&(t.navigator.epubReadingSystem.layoutStyle=`paginated`);let r=t.document.createElement(`style`);r.dataset.readium=`true`,r.id=xs,r.textContent=`
        @keyframes readium-bounce-l-animation {
            0%, 100% {transform: translate3d(0, 0, 0);}
            50% {transform: translate3d(-50px, 0, 0);}
        }

        @keyframes readium-bounce-r-animation {
            0%, 100% {transform: translate3d(0, 0, 0);}
            50% {transform: translate3d(50px, 0, 0);}
        }

        .readium-bounce-l {
            animation: readium-bounce-l-animation 150ms ease-out 1;
        }

        .readium-bounce-r {
            animation: readium-bounce-r-animation 150ms ease-out 1;
        }

        html {
            overflow: hidden;
        }

        body {
            -ms-overflow-style: none; /* for Internet Explorer, Edge */
        }

        * {
            scrollbar-width: none; /* for Firefox */
        }

        body::-webkit-scrollbar {
            display: none; /* for Chrome, Safari, and Opera */
        }
        `,t.document.head.appendChild(r),this.resizeObserver=new ResizeObserver(()=>{t.requestAnimationFrame(()=>{t&&Pa(t)}),this.onWidthChange()}),this.resizeObserver.observe(t.document.body),this.mutationObserver=new MutationObserver(e=>{for(let n of e)if(n.target===this.wnd.document.documentElement){let e=n.oldValue,r=n.target.getAttribute(`style`),i=/transform\s*:\s*([^;]+)/,a=e?.match(i),o=r?.match(i);(!a&&!o&&za(e,r)||a&&!o||a&&o&&a[1]!==o[1])&&(t.requestAnimationFrame(()=>{t&&Pa(t)}),this.onWidthChange())}else t.requestAnimationFrame(()=>this.cachedScrollWidth=this.doc().scrollWidth)}),t.frameElement&&this.mutationObserver.observe(t.frameElement,{attributes:!0,attributeFilter:[`style`]}),this.mutationObserver.observe(t.document,{attributes:!0,attributeFilter:[`style`]}),this.mutationObserver.observe(t.document.documentElement,{attributes:!0,attributeFilter:[`style`]}),n.register(`scroll_protection`,e.moduleName,(e,t)=>{this.enableSnapProtection(),t(!0)});let i=e=>{let t=this.doc().scrollLeft;return this.doc().scrollLeft=this.snapOffset(e),t!==this.doc().scrollLeft},a=e=>{let n=this.doc().scrollLeft,r=this.snapNormOffset(Math.max(0,Math.min(this.cachedScrollWidth-t.innerWidth,e)));return this.doc().scrollLeft=-r,n!==this.doc().scrollLeft};return t.addEventListener(`orientationchange`,this.onWidthChanger),t.addEventListener(`resize`,this.onWidthChanger),t.requestAnimationFrame(()=>this.cachedScrollWidth=this.doc().scrollWidth),n.register(`go_progression`,e.moduleName,(e,r)=>{let i=e;i<0||i>1?(n.send(`error`,{message:`go_progression must be given a position from 0.0 to 1.0`}),r(!1)):this.wnd.requestAnimationFrame(()=>{this.cachedScrollWidth=this.doc().scrollWidth;let e=(this.cachedScrollWidth-t.innerWidth)*i;this.rtl?this.doc().scrollLeft=-this.snapNormOffset(e):this.doc().scrollLeft=this.snapOffset(e),this.reportProgress(),H(this.wnd),r(!0)})}),n.register(`go_id`,e.moduleName,(e,n)=>{let r=t.document.getElementById(e);r?this.wnd.requestAnimationFrame(()=>{this.rtl?this.doc().scrollLeft=-this.snapNormOffset(r.getBoundingClientRect().left+t.scrollX):this.doc().scrollLeft=this.snapOffset(r.getBoundingClientRect().left+t.scrollX);let i=e;this.reportProgress(this.timelineEntries.has(i)?i:this.nearestPrecedingTimelineEntry(r)),H(this.wnd),n(!0)}):n(!1)}),n.register(`go_text`,e.moduleName,(e,n)=>{let r;Array.isArray(e)&&(e.length>1&&(r=e[1]),e=e[0]);let i=A.deserialize(e),a=as(this.wnd.document,new j({href:t.location.href,type:`text/html`,text:i,locations:r?new k({otherLocations:new Map([[`cssSelector`,r]])}):void 0}));a?this.wnd.requestAnimationFrame(()=>{this.rtl?this.doc().scrollLeft=-this.snapNormOffset(a.getBoundingClientRect().left+t.scrollX):this.doc().scrollLeft=this.snapOffset(a.getBoundingClientRect().left+t.scrollX),this.reportProgress(this.nearestPrecedingTimelineEntry(a.startContainer)),H(this.wnd),n(!0)}):n(!1)}),n.register(`go_end`,e.moduleName,(e,n)=>{this.wnd.requestAnimationFrame(()=>{this.cachedScrollWidth=this.doc().scrollWidth;let e;if(e=this.rtl?-this.snapNormOffset(this.cachedScrollWidth-t.innerWidth):this.snapOffset(this.cachedScrollWidth),this.doc().scrollLeft===e)return n(!1);this.doc().scrollLeft=e,this.reportProgress(this.sortedFragmentIds[this.sortedFragmentIds.length-1]),H(this.wnd),n(!0)})}),n.register(`go_start`,e.moduleName,(e,t)=>{this.wnd.requestAnimationFrame(()=>{if(this.doc().scrollLeft===0)return t(!1);this.doc().scrollLeft=0,this.reportProgress(this.firstFragmentIfReached()),H(this.wnd),t(!0)})}),n.register(`go_prev`,e.moduleName,(e,n)=>{this.wnd.requestAnimationFrame(()=>{this.cachedScrollWidth=this.doc().scrollWidth;let e;e=this.rtl?a(this.normScroll()-t.innerWidth):i(t.scrollX-t.innerWidth),this.reportProgress(),e&&(H(this.wnd),this.checkSuspiciousSnap(`left`,this.wnd.innerWidth)),n(e)})}),n.register(`go_next`,e.moduleName,(e,n)=>{this.wnd.requestAnimationFrame(()=>{this.cachedScrollWidth=this.doc().scrollWidth;let e;e=this.rtl?a(this.normScroll()+t.innerWidth):i(t.scrollX+t.innerWidth),this.reportProgress(),e&&(H(this.wnd),this.checkSuspiciousSnap(`right`,this.wnd.innerWidth)),n(e)})}),n.register(`unfocus`,e.moduleName,(e,t)=>{this.snappingCancelled=!0,H(this.wnd),t(!0)}),n.register(`shake`,e.moduleName,(e,t)=>{this.shake(),t(!0)}),n.register(`focus`,e.moduleName,(e,t)=>{this.wnd.requestAnimationFrame(()=>{this.cachedScrollWidth=this.doc().scrollWidth,this.snapCurrentOffset(!1,!0),this.reportProgress(),t(!0)})}),n.register(`first_visible_locator`,e.moduleName,(e,n)=>{let r=ds(t,!1);this.comms.send(`first_visible_locator`,r.serialize()),n(!0)}),n.register(`timeline_entries`,e.moduleName,(e,n)=>{this.updateTimelineEntries(Array.isArray(e)?e:[],t),t.requestAnimationFrame(()=>this.reportProgress()),n(!0)}),t.addEventListener(`touchstart`,this.onTouchStarter,{passive:!0}),t.addEventListener(`touchend`,this.onTouchEnder,{passive:!0}),t.addEventListener(`touchmove`,this.onTouchMover,{passive:!0}),t.document.addEventListener(`touchstart`,()=>{}),n.log(`ColumnSnapper Mounted`),!0}unmount(t,n){return this.snappingCancelled=!0,n.unregisterAll(e.moduleName),this.resizeObserver.disconnect(),this.mutationObserver.disconnect(),this.patternAnalyzer&&(this.patternAnalyzer.clear(),this.patternAnalyzer=null,this.isSnapProtectionEnabled=!1),t.removeEventListener(`touchstart`,this.onTouchStarter),t.removeEventListener(`touchend`,this.onTouchEnder),t.removeEventListener(`touchmove`,this.onTouchMover),t.removeEventListener(`orientationchange`,this.onWidthChanger),t.removeEventListener(`resize`,this.onWidthChanger),t.document.getElementById(xs)?.remove(),this.timelineEntries.clear(),n.log(`ColumnSnapper Unmounted`),super.unmount(t,n)}};Cs.moduleName=`column_snapper`;var ws=Cs,Ts=`readium-scroll-snapper-style`,Es=class e extends z{constructor(){super(...arguments),this.patternAnalyzer=null,this.lastScrollTime=0,this.isScrollProtectionEnabled=!1,this.initialScrollHandled=!1,this.isScrolling=!1,this.lastScrollTop=0,this.isResizing=!1,this.resizeDebounce=null,this.handleScroll=e=>{if(this.comms.ready&&!this.isResizing){if(!this.initialScrollHandled){this.lastScrollTop=this.doc().scrollTop,this.initialScrollHandled=!0,this.reportProgress();return}this.isScrolling||(this.isScrolling=!0,this.wnd.requestAnimationFrame(()=>{this.reportProgress();let t=this.doc().scrollTop,n=t-this.lastScrollTop;if(this.lastScrollTop=t,this.isScrollProtectionEnabled&&Math.abs(n)>5){let t=Date.now(),r=t-(this.lastScrollTime||t);if(this.patternAnalyzer&&this.patternAnalyzer.analyze(n>0?`down`:`up`,Math.abs(n),r)){let t=e.target&&`tagName`in e.target?{tagName:e.target.tagName}:null;this.comms?.send(`content_protection`,{type:`suspicious_scrolling`,timestamp:Date.now(),scrollDelta:n,scrollDirection:n>0?`down`:`up`,targetElement:t})}this.lastScrollTime=t}this.comms.send(`scroll`,n),this.isScrolling=!1}))}}}doc(){return this.wnd.document.scrollingElement}hasScrolledPast(e){let t=this.wnd.innerHeight/2;return e.getBoundingClientRect().top<=t+this.wnd.innerHeight*z.CENTER_TOLERANCE}inCenterBand(e){let t=e.getBoundingClientRect(),n=this.wnd.innerHeight/2,r=this.wnd.innerHeight*z.CENTER_TOLERANCE,i=n-r,a=n+r;return t.height===0?t.top<=a&&t.top>=i:Math.max(0,Math.min(t.bottom,a)-Math.max(t.top,i))/t.height>=z.CENTER_TOLERANCE}fragmentStart(e){return e.getBoundingClientRect().top+this.doc().scrollTop}currentScrollExtent(){return{pos:this.doc().scrollTop,size:this.wnd.innerHeight}}reportProgress(e){if(!this.comms.ready)return;let t=Math.ceil(this.doc().scrollTop),n=this.doc().scrollHeight,r=this.wnd.innerHeight,i=Math.max(0,Math.min(1,t/n)),a=Math.max(0,Math.min(1,(t+r)/n));this.comms.send(`progress`,{start:i,end:a,fragmentId:e===void 0?this.currentTimelineFragment():e,visibleFragmentIds:this.sortedVisibleFragmentIds()})}enableScrollProtection(){this.patternAnalyzer||(this.patternAnalyzer=new bs(_s),this.isScrollProtectionEnabled=!0,this.comms?.log(`Scroll protection enabled`))}mount(t,n){this.wnd=t,this.comms=n,this.initialScrollHandled=!1,this.lastScrollTop=0,this.isResizing=!1,this.resizeDebounce&&=(this.wnd.clearTimeout(this.resizeDebounce),null),t.navigator.epubReadingSystem&&(t.navigator.epubReadingSystem.layoutStyle=`scrolling`);let r=t.document.createElement(`style`);return r.dataset.readium=`true`,r.id=Ts,r.textContent=`
        * {
            scrollbar-width: none; /* for Firefox */
        }

        body::-webkit-scrollbar {
            display: none; /* for Chrome, Safari, and Opera */
        }
        `,t.document.head.appendChild(r),this.resizeObserver=new ResizeObserver(()=>{this.resizeDebounce&&this.wnd.clearTimeout(this.resizeDebounce),this.isResizing=!0,this.resizeDebounce=this.wnd.setTimeout(()=>{this.isResizing=!1,this.resizeDebounce=null,this.refreshFragmentStarts(),this.reportProgress()},50)}),this.resizeObserver.observe(t.document.body),t.addEventListener(`scroll`,this.handleScroll,{passive:!0}),n.register(`force_webkit_recalc`,e.moduleName,()=>{Fa(this.wnd);let e=this.doc().scrollTop;e>1?this.doc().scrollTop=e-1:this.doc().scrollTop=e+1,this.doc().scrollTop=e}),n.register(`go_progression`,e.moduleName,(e,t)=>{let r=e;r<0||r>1?(n.send(`error`,{message:`go_progression must be given a position from 0.0 to 1.0`}),t(!1)):this.wnd.requestAnimationFrame(()=>{this.doc().scrollTop=this.doc().offsetHeight*r,this.reportProgress(this.fragmentFromGeometry()),H(this.wnd),t(!0)})}),n.register(`go_id`,e.moduleName,(e,n)=>{let r=t.document.getElementById(e);r?this.wnd.requestAnimationFrame(()=>{this.doc().scrollTop=r.getBoundingClientRect().top+t.scrollY-t.innerHeight/2;let i=e;this.reportProgress(this.timelineEntries.has(i)?i:this.nearestPrecedingTimelineEntry(r)),H(this.wnd),n(!0)}):n(!1)}),n.register(`go_text`,e.moduleName,(e,n)=>{let r;Array.isArray(e)&&(e.length>1&&(r=e[1]),e=e[0]);let i=A.deserialize(e),a=as(this.wnd.document,new j({href:t.location.href,type:`text/html`,text:i,locations:r?new k({otherLocations:new Map([[`cssSelector`,r]])}):void 0}));a?this.wnd.requestAnimationFrame(()=>{this.doc().scrollTop=a.getBoundingClientRect().top+t.scrollY-t.innerHeight/2,this.reportProgress(this.nearestPrecedingTimelineEntry(a.startContainer)),H(this.wnd),n(!0)}):n(!1)}),n.register(`go_start`,e.moduleName,(e,t)=>{if(this.doc().scrollTop===0)return t(!1);this.doc().scrollTop=0,this.reportProgress(this.firstFragmentIfReached()),t(!0)}),n.register(`go_end`,e.moduleName,(e,t)=>{if(this.doc().scrollTop===this.doc().scrollHeight-this.doc().offsetHeight)return t(!1);this.doc().scrollTop=this.doc().scrollHeight-this.doc().offsetHeight,this.reportProgress(this.sortedFragmentIds[this.sortedFragmentIds.length-1]),t(!0)}),n.register(`unfocus`,e.moduleName,(e,t)=>{H(this.wnd),t(!0)}),n.register(`scroll_protection`,e.moduleName,(e,t)=>{this.enableScrollProtection(),t(!0)}),n.register([`go_next`,`go_prev`],e.moduleName,(e,t)=>t(!1)),n.register(`focus`,e.moduleName,(e,t)=>{this.reportProgress(),t(!0)}),n.register(`first_visible_locator`,e.moduleName,(e,n)=>{let r=ds(t,!0);this.comms.send(`first_visible_locator`,r.serialize()),n(!0)}),n.register(`timeline_entries`,e.moduleName,(e,n)=>{this.updateTimelineEntries(Array.isArray(e)?e:[],t),n(!0)}),n.log(`ScrollSnapper Mounted`),!0}unmount(t,n){return n.unregisterAll(e.moduleName),this.resizeObserver.disconnect(),this.handleScroll&&t.removeEventListener(`scroll`,this.handleScroll),t.document.getElementById(Ts)?.remove(),this.timelineEntries.clear(),this.cachedFragmentIds=[],this.sortedFragmentIds=[],this.cachedFragmentStarts.clear(),this.patternAnalyzer&&(this.patternAnalyzer.clear(),this.patternAnalyzer=null,this.isScrollProtectionEnabled=!1),n.log(`ScrollSnapper Unmounted`),!0}};Es.moduleName=`scroll_snapper`;var Ds=Es,Os=class e extends z{constructor(){super(...arguments),this.patternAnalyzer=null,this.lastScrollTime=0,this.isScrollProtectionEnabled=!1,this.initialScrollHandled=!1,this.isScrolling=!1,this.lastScrollTop=0,this.isResizing=!1,this.resizeDebounce=null,this.handleScroll=e=>{if(this.comms.ready&&!this.isResizing){if(!this.initialScrollHandled){this.lastScrollTop=this.doc().scrollTop,this.initialScrollHandled=!0,this.reportProgress();return}this.isScrolling||(this.isScrolling=!0,this.wnd.requestAnimationFrame(()=>{this.reportProgress();let t=this.doc().scrollTop,n=t-this.lastScrollTop;if(this.lastScrollTop=t,this.isScrollProtectionEnabled&&Math.abs(n)>5){let t=Date.now(),r=t-(this.lastScrollTime||t);if(this.patternAnalyzer&&this.patternAnalyzer.analyze(n>0?`down`:`up`,Math.abs(n),r)){let t=e.target&&`tagName`in e.target?{tagName:e.target.tagName}:null;this.comms?.send(`content_protection`,{type:`suspicious_scrolling`,timestamp:Date.now(),scrollDelta:n,scrollDirection:n>0?`down`:`up`,targetElement:t})}this.lastScrollTime=t}this.comms.send(`scroll`,n),this.isScrolling=!1}))}}}doc(){return this.wnd.document.scrollingElement}hasScrolledPast(e){let t=this.wnd.innerHeight/2;return e.getBoundingClientRect().top<=t+this.wnd.innerHeight*z.CENTER_TOLERANCE}inCenterBand(e){let t=e.getBoundingClientRect(),n=this.wnd.innerHeight/2,r=this.wnd.innerHeight*z.CENTER_TOLERANCE,i=n-r,a=n+r;return t.height===0?t.top<=a&&t.top>=i:Math.max(0,Math.min(t.bottom,a)-Math.max(t.top,i))/t.height>=z.CENTER_TOLERANCE}fragmentStart(e){return e.getBoundingClientRect().top+this.doc().scrollTop}currentScrollExtent(){return{pos:this.doc().scrollTop,size:this.wnd.innerHeight}}reportProgress(e){if(!this.comms.ready)return;let t=Math.ceil(this.doc().scrollTop),n=this.doc().scrollHeight,r=this.wnd.innerHeight,i=Math.max(0,Math.min(1,t/n)),a=Math.max(0,Math.min(1,(t+r)/n));this.comms.send(`progress`,{start:i,end:a,fragmentId:e===void 0?this.currentTimelineFragment():e,visibleFragmentIds:this.sortedVisibleFragmentIds()})}enableScrollProtection(){this.patternAnalyzer||(this.patternAnalyzer=new bs(_s),this.isScrollProtectionEnabled=!0,this.comms?.log(`Scroll protection enabled`))}mount(t,n){return this.wnd=t,this.comms=n,this.initialScrollHandled=!1,this.lastScrollTop=0,this.isResizing=!1,this.resizeDebounce&&=(this.wnd.clearTimeout(this.resizeDebounce),null),this.resizeObserver=new ResizeObserver(()=>{this.resizeDebounce&&this.wnd.clearTimeout(this.resizeDebounce),this.isResizing=!0,this.resizeDebounce=this.wnd.setTimeout(()=>{this.isResizing=!1,this.resizeDebounce=null,this.refreshFragmentStarts(),this.reportProgress()},50)}),this.resizeObserver.observe(t.document.body),t.addEventListener(`scroll`,this.handleScroll,{passive:!0}),n.register(`force_webkit_recalc`,e.moduleName,()=>{Fa(this.wnd);let e=this.doc().scrollTop;e>1?this.doc().scrollTop=e-1:this.doc().scrollTop=e+1,this.doc().scrollTop=e}),n.register(`go_progression`,e.moduleName,(e,t)=>{let r=e;r<0||r>1?(n.send(`error`,{message:`go_progression must be given a position from 0.0 to 1.0`}),t(!1)):this.wnd.requestAnimationFrame(()=>{this.doc().scrollTop=this.doc().offsetHeight*r,this.reportProgress(this.fragmentFromGeometry()),H(this.wnd),t(!0)})}),n.register(`go_id`,e.moduleName,(e,n)=>{let r=t.document.getElementById(e);r?this.wnd.requestAnimationFrame(()=>{this.doc().scrollTop=r.getBoundingClientRect().top+t.scrollY-t.innerHeight/2;let i=e;this.reportProgress(this.timelineEntries.has(i)?i:this.nearestPrecedingTimelineEntry(r)),H(this.wnd),n(!0)}):n(!1)}),n.register(`go_text`,e.moduleName,(e,n)=>{let r;Array.isArray(e)&&(e.length>1&&(r=e[1]),e=e[0]);let i=A.deserialize(e),a=as(this.wnd.document,new j({href:t.location.href,type:`text/html`,text:i,locations:r?new k({otherLocations:new Map([[`cssSelector`,r]])}):void 0}));a?this.wnd.requestAnimationFrame(()=>{this.doc().scrollTop=a.getBoundingClientRect().top+t.scrollY-t.innerHeight/2,this.reportProgress(this.nearestPrecedingTimelineEntry(a.startContainer)),H(this.wnd),n(!0)}):n(!1)}),n.register(`go_start`,e.moduleName,(e,t)=>{if(this.doc().scrollTop===0)return t(!1);this.doc().scrollTop=0,this.reportProgress(this.firstFragmentIfReached()),t(!0)}),n.register(`go_end`,e.moduleName,(e,t)=>{if(this.doc().scrollTop===this.doc().scrollHeight-this.doc().offsetHeight)return t(!1);this.doc().scrollTop=this.doc().scrollHeight-this.doc().offsetHeight,this.reportProgress(this.sortedFragmentIds[this.sortedFragmentIds.length-1]),t(!0)}),n.register(`unfocus`,e.moduleName,(e,t)=>{H(this.wnd),t(!0)}),n.register(`scroll_protection`,e.moduleName,(e,t)=>{this.enableScrollProtection(),t(!0)}),n.register([`go_next`,`go_prev`],e.moduleName,(e,t)=>t(!1)),n.register(`focus`,e.moduleName,(e,t)=>{this.reportProgress(),t(!0)}),n.register(`first_visible_locator`,e.moduleName,(e,r)=>{let i=ds(t,!0);n.send(`first_visible_locator`,i.serialize()),r(!0)}),n.register(`timeline_entries`,e.moduleName,(e,n)=>{this.updateTimelineEntries(Array.isArray(e)?e:[],t),n(!0)}),n.log(`WebPubSnapper Mounted`),!0}unmount(t,n){return n.unregisterAll(e.moduleName),this.resizeObserver.disconnect(),this.handleScroll&&t.removeEventListener(`scroll`,this.handleScroll),this.patternAnalyzer&&(this.patternAnalyzer.clear(),this.patternAnalyzer=null,this.isScrollProtectionEnabled=!1),this.timelineEntries.clear(),this.cachedFragmentIds=[],this.sortedFragmentIds=[],this.cachedFragmentStarts.clear(),n.log(`WebPubSnapper Unmounted`),!0}};Os.moduleName=`webpub_snapper`;var ks=Os,As=class{constructor(e,t){this.window=e,this.copyHistory=[],this.lastSelectionLength=0,this.lastSelectionTime=0,this.options=t}cleanupOldHistory(e){this.copyHistory=this.copyHistory.filter(t=>e-t.timestamp<1e4),this.copyHistory.length>this.options.historySize&&(this.copyHistory=this.copyHistory.slice(-this.options.historySize))}isSuspiciousPattern(e){return this.copyHistory.length<3?!1:this.copyHistory.filter(t=>e-t.timestamp<2e3).length>=3||this.copyHistory.slice().sort((e,t)=>e.timestamp-t.timestamp).every((e,t,n)=>t===0||e.length>n[t-1].length*1.5)}shouldAllowCopy(e){if(!this.options.enabled)return!0;let t=this.window.getSelection();if(!t)return!0;let n=t.toString().length,r=this.window.document.body.innerText.length,i=Date.now();if(this.cleanupOldHistory(i),n<this.options.minThreshold)return this.copyHistory.push({timestamp:i,length:n,wasBlocked:!1}),!0;let a=i-this.lastSelectionTime<100&&n>this.lastSelectionLength*1.5,o=Math.min(r*this.options.maxSelectionPercent,this.options.absoluteMaxChars),s=this.isSuspiciousPattern(i),c=n>o||a||s;return this.copyHistory.push({timestamp:i,length:n,wasBlocked:c}),c?(e?.preventDefault(),!1):(this.lastSelectionLength=n,this.lastSelectionTime=i,!0)}destroy(){this.lastSelectionLength=0,this.lastSelectionTime=0,this.copyHistory=[],this.options.enabled=!1}},js=class{constructor(e=vs){this.options=e,this.events=[],this.selectionStartTime=0,this.lastSelectionTime=0,this.lastSelectionPosition=0,this.selectionPatterns=[],this.lastSelectedText=``}analyze(e){if(!e)return this.clear(),!1;let t=e.toString();if(t.length===0)return this.clear(),!1;if(e.type!==`Range`||!e.rangeCount)return!1;let n=Date.now();if(t.length<=50||t===this.lastSelectedText)return!1;if(this.selectionStartTime===0)return this.selectionStartTime=n,this.lastSelectedText=t,!1;if(n-this.selectionStartTime<500)return!1;n-this.lastSelectionTime>1e3&&(this.lastSelectionTime=n),this.selectionStartTime===0&&(this.selectionStartTime=n),this.lastSelectedText=t;let r=this.analyzeSelectionPattern(e,n);return this.cleanup(n),r}analyzeSelectionPattern(e,t){if(!e.rangeCount)return!1;let n=e.getRangeAt(0),r=n.toString(),i=(t-this.selectionStartTime)/1e3;if(r.length/Math.max(1,i)>this.options.maxSelectionsPerSecond)return!0;let a=n.startOffset,o=Math.abs(a-this.lastSelectionPosition);return this.selectionPatterns.push(o),this.selectionPatterns.length>this.options.historySize&&(this.selectionPatterns.shift(),this.calculateVariance(this.selectionPatterns)<this.options.minVariance)||(this.lastSelectionPosition=a,!1)}calculateVariance(e){if(e.length===0)return 0;let t=e.reduce((e,t)=>e+t,0)/e.length;return e.reduce((e,n)=>e+(n-t)**2,0)/e.length}cleanup(e){this.events=this.events.filter(t=>e-t.timestamp<=1e3)}clear(){this.events=[],this.selectionStartTime=0,this.lastSelectionTime=0,this.lastSelectionPosition=0,this.selectionPatterns=[],this.lastSelectedText=``}},Ms=class{match(e,t){for(let n of t)if(this.matchesCombo(e,n))return!0;return!1}matchesCombo(e,t){return e.keyCode===t.keyCode&&this.matchesModifier(e.ctrlKey,t.ctrl)&&this.matchesModifier(e.shiftKey,t.shift)&&this.matchesModifier(e.altKey,t.alt)&&this.matchesModifier(e.metaKey,t.meta)}matchesModifier(e,t){return t===void 0?!e:e===t}createKeyHandler(e,t){return n=>{this.match(n,e)&&(n.preventDefault(),n.stopPropagation(),t(n))}}createActivityEvent(e,t,n,r){let i,a;if(r){let e=r.getSelection(),t=e?.toString()||``,n=(t&&e?.rangeCount?e.getRangeAt(0)?.getClientRects():null)?.[0];n&&t&&(i={text:t,x:n.x,y:n.y,width:n.width,height:n.height});let o=r.document.activeElement;o&&o!==r.document.body&&(a=cs(o)?.outerHTML)}return{type:t,timestamp:Date.now(),key:e.key,code:e.code,keyCode:e.keyCode,ctrlKey:e.ctrlKey,altKey:e.altKey,shiftKey:e.shiftKey,metaKey:e.metaKey,targetFrameSrc:n,selectedText:i,interactiveElement:a}}createKeyboardHandlers(e,t,n,r){let i=[];return t.forEach(t=>{i.push(...t.keyCombos.map(i=>({...i,handler:i=>{let a=t.type;n(this.createActivityEvent(i,a,e,r))}})))}),i}createUnifiedHandler(e,t,n,r){let i=this.createKeyboardHandlers(e,t,n,r);return e=>{if(e.isTrusted){for(let t of i)if(this.match(e,[t])){let n=t.suppressOnInteractiveElement;if(n){let e=(r?.document??document).activeElement;if(Array.isArray(n)?n.some(t=>e?.matches(t)):us(e))return}e.preventDefault(),e.stopPropagation(),t.handler(e);return}}}}},Ns=class e extends Ta{constructor(){super(...arguments),this.configApplied=!1,this.cleanupCallbacks=[],this.pointerMoved=!1,this.isContextMenuEnabled=!1,this.isDragAndDropEnabled=!1,this.isSelectionMonitoringEnabled=!1,this.isBulkCopyProtectionEnabled=!1,this.selectionAnalyzer=null,this.currentSelection=null,this.bulkCopyProtector=null,this.keyManager=new Ms,this.keyDownHandler=null,this.preventBulkCopy=e=>{if(!this.isBulkCopyProtectionEnabled||!this.bulkCopyProtector)return!0;if(!this.bulkCopyProtector.shouldAllowCopy(e)){e.preventDefault();let t=this.wnd.getSelection(),n=t?.toString()||``,r=(n?t?.getRangeAt(0)?.getClientRects():null)?.[0],i={type:`bulk_copy`,timestamp:Date.now(),clipboardTypes:e.clipboardData?.types?[...e.clipboardData.types]:[],selectedText:r?{text:n,x:r.x,y:r.y,width:r.width,height:r.height}:void 0,selectionLength:n.length,targetFrameSrc:this.wnd.location.href};return this.comms?.send(`content_protection`,i),!1}return!0},this.handleSelection=e=>{if(!this.isSelectionMonitoringEnabled||!this.wnd||!this.selectionAnalyzer)return;let t=this.wnd.getSelection();if(t){if(this.currentSelection=t.toString(),this.selectionAnalyzer.analyze(t)&&this.currentSelection){let t=this.wnd.getSelection(),n=t?.toString()||``,r=(n&&t?.rangeCount?t.getRangeAt(0)?.getClientRects():null)?.[0],i={type:`suspicious_selection`,timestamp:Date.now(),selectionLength:n.length,selectedText:{text:n,x:r?.x??0,y:r?.y??0,width:r?.width??0,height:r?.height??0},eventType:e?.type||`selectionchange`,targetFrameSrc:this.wnd.location.href};this.comms?.send(`content_protection`,i)}}else this.currentSelection=null},this.onDragOver=e=>{this.isDragAndDropEnabled&&(e.preventDefault(),e.stopPropagation())},this.onDragStart=e=>{if(this.isDragAndDropEnabled){e.preventDefault();let t={type:`drag_detected`,timestamp:Date.now(),dataTransferTypes:e.dataTransfer?.types?[...e.dataTransfer.types]:[],targetFrameSrc:this.wnd.location.href};return this.comms?.send(`content_protection`,t),!1}return!0},this.onDrop=e=>{if(this.isDragAndDropEnabled){e.preventDefault();let t=e.dataTransfer,n={type:`drop_detected`,timestamp:Date.now(),dataTransferTypes:t?.types?[...t.types]:[],fileCount:t?.files?.length||0,targetFrameSrc:this.wnd.location.href};return this.comms?.send(`content_protection`,n),!1}return!0},this.onContext=e=>{if(this.isContextMenuEnabled){e.preventDefault();let t=this.wnd.getSelection(),n=t?.toString()||``,r=(n&&t?.rangeCount?t.getRangeAt(0)?.getClientRects():null)?.[0],i={timestamp:Date.now(),clientX:e.clientX,clientY:e.clientY,...r&&{selectedText:{text:n,x:r.x,y:r.y,width:r.width,height:r.height}},targetFrameSrc:this.wnd.location.href};this.comms?.send(`context_menu`,i)}},this.onPointerUp=this.onPointUp.bind(this),this.onPointerMove=this.onPointMove.bind(this),this.onPointerDown=this.onPointDown.bind(this),this.onClicker=this.onClick.bind(this)}addContextMenuPrevention(){this.isContextMenuEnabled||!this.wnd||(this.wnd.document.addEventListener(`contextmenu`,this.onContext),this.isContextMenuEnabled=!0)}removeContextMenuPrevention(){!this.isContextMenuEnabled||!this.wnd||(this.wnd.document.removeEventListener(`contextmenu`,this.onContext),this.isContextMenuEnabled=!1)}addDragAndDropPrevention(){this.isDragAndDropEnabled||!this.wnd||(this.wnd.document.addEventListener(`dragstart`,this.onDragStart),this.wnd.document.addEventListener(`dragover`,this.onDragOver),this.wnd.document.addEventListener(`drop`,this.onDrop),this.isDragAndDropEnabled=!0)}removeDragAndDropPrevention(){!this.isDragAndDropEnabled||!this.wnd||(this.wnd.document.removeEventListener(`dragstart`,this.onDragStart),this.wnd.document.removeEventListener(`dragover`,this.onDragOver),this.wnd.document.removeEventListener(`drop`,this.onDrop),this.isDragAndDropEnabled=!1)}enableKeyboardPeripherals(e=[]){this.disableKeyboardPeripherals();let t=e=>{this.comms?.send(`keyboard_peripherals`,e)};this.keyDownHandler=this.keyManager.createUnifiedHandler(this.wnd.location.href,e,t,this.wnd),this.wnd&&this.wnd.document.addEventListener(`keydown`,this.keyDownHandler,{capture:!0})}disableKeyboardPeripherals(){this.wnd&&this.keyDownHandler&&(this.wnd.document.removeEventListener(`keydown`,this.keyDownHandler,{capture:!0}),this.keyDownHandler=null)}addBulkCopyProtection(e={}){if(this.isBulkCopyProtectionEnabled||!this.wnd)return;let t=ys,n=e?{...t,...e}:t;this.bulkCopyProtector=new As(this.wnd,n),this.wnd.document.addEventListener(`copy`,this.preventBulkCopy,!0),this.wnd.document.addEventListener(`cut`,this.preventBulkCopy,!0),this.isBulkCopyProtectionEnabled=!0}removeBulkCopyProtection(){!this.isBulkCopyProtectionEnabled||!this.wnd||(this.wnd.document.removeEventListener(`copy`,this.preventBulkCopy,!0),this.wnd.document.removeEventListener(`cut`,this.preventBulkCopy,!0),this.bulkCopyProtector?.destroy(),this.bulkCopyProtector=null,this.isBulkCopyProtectionEnabled=!1)}addSelectionMonitoring(e){if(this.isSelectionMonitoringEnabled||!this.wnd)return;let t=e||vs;this.selectionAnalyzer=new js(t),this.wnd.document.addEventListener(`selectionchange`,this.handleSelection),this.isSelectionMonitoringEnabled=!0}removeSelectionMonitoring(){!this.isSelectionMonitoringEnabled||!this.wnd||(this.wnd.document.removeEventListener(`selectionchange`,this.handleSelection),this.selectionAnalyzer?.clear(),this.selectionAnalyzer=null,this.isSelectionMonitoringEnabled=!1)}onPointUp(e){let t=this.wnd.getSelection();if(t&&t.toString()?.length>0){let e=t.getRangeAt(0)?.getClientRects();if(!e||e.length===0)return;let n=e[0],r={text:t.toString(),x:n.x,y:n.y,width:n.width,height:n.height,targetFrameSrc:this.wnd?.location?.href};this.comms.send(`text_selected`,r)}if(this.pointerMoved){this.pointerMoved=!1;return}if(!t?.isCollapsed||!e.isPrimary)return;let n=this.wnd.devicePixelRatio;e.preventDefault(),this.comms.send(e.pointerType===`touch`?`tap`:`click`,{defaultPrevented:e.defaultPrevented,x:e.clientX*n,y:e.clientY*n,targetFrameSrc:this.wnd.location.href,targetElement:e.target.outerHTML,interactiveElement:cs(e.target)?.outerHTML,cssSelector:this.wnd._readium_cssSelectorGenerator.getCssSelector(e.target)}),this.pointerMoved=!1}onPointMove(e){e.movementY!==void 0&&e.movementX!==void 0?(Math.abs(e.movementX)>1||Math.abs(e.movementY)>1)&&(this.pointerMoved=!0):this.pointerMoved=!0}onPointDown(){this.pointerMoved=!1}onClick(e){if(e.preventDefault(),!e.isTrusted){let t=new PointerEvent(`pointerup`,{isPrimary:!0,pointerType:`mouse`,clientX:e.clientX,clientY:e.clientY});Object.defineProperty(t,"target",{writable:!1,value:e.target}),Object.defineProperty(t,"defaultPrevented",{writable:!1,value:e.defaultPrevented}),this.onPointUp(t)}}registerProtectionHandlers(){this.comms?.register(`peripherals_protection`,e.moduleName,(e,t)=>{let n=e;if(!this.configApplied){if(this.configApplied=!0,n.monitorSelection){let e=typeof n.monitorSelection==`boolean`?void 0:n.monitorSelection;this.addSelectionMonitoring(e),this.comms?.log(`Selection monitoring enabled`)}typeof n.protectCopy==`object`?(this.addBulkCopyProtection({enabled:!0,...n.protectCopy}),this.comms?.log(`Copy protection enabled (limited)`)):n.protectCopy===!0&&(this.addBulkCopyProtection({enabled:!0,maxSelectionPercent:0,minThreshold:0,absoluteMaxChars:0}),this.comms?.log(`Copy protection enabled`)),n.disableContextMenu&&(this.addContextMenuPrevention(),this.comms?.log(`Context menu protection enabled`)),n.disableDragAndDrop&&(this.addDragAndDropPrevention(),this.comms?.log(`Drag and drop protection enabled`))}t(!0)}),this.comms?.register(`unfocus`,e.moduleName,(e,t)=>{this.disableKeyboardPeripherals(),t(!0)}),this.comms?.register(`keyboard_peripherals`,e.moduleName,(e,t)=>{let n=e;n&&n.length>0&&(this.enableKeyboardPeripherals(n),this.comms?.log(`Keyboard peripherals enabled: ${n.map(e=>e.type).join(`, `)}`)),t(!0)})}mount(e,t){return this.wnd=e,this.comms=t,this.registerProtectionHandlers(),e.document.addEventListener(`pointerdown`,this.onPointerDown),e.document.addEventListener(`pointerup`,this.onPointerUp),e.document.addEventListener(`pointermove`,this.onPointerMove),e.document.addEventListener(`click`,this.onClicker),t.log(`Peripherals Mounted`),!0}unmount(t,n){return this.removeBulkCopyProtection(),this.removeSelectionMonitoring(),this.removeContextMenuPrevention(),this.removeDragAndDropPrevention(),this.disableKeyboardPeripherals(),this.cleanupCallbacks.forEach(e=>e()),this.cleanupCallbacks=[],t.document.removeEventListener(`pointerdown`,this.onPointerDown),t.document.removeEventListener(`pointerup`,this.onPointerUp),t.document.removeEventListener(`pointermove`,this.onPointerMove),t.document.removeEventListener(`click`,this.onClicker),n.unregisterAll(e.moduleName),this.configApplied=!1,n.log(`Peripherals Unmounted`),!0}};Ns.moduleName=`peripherals`;var Ps=Ns,Fs=class e extends Ta{constructor(){super(...arguments),this.mediaPlayingCount=0,this.allAnimations=new Set}wndOnErr(e){this.comms?.send(`error`,{message:e.message,filename:e.filename,lineno:e.lineno,colno:e.colno})}unblock(e){for(e._readium_blockEvents=!1;e._readium_blockedEvents?.length>0;){let t=e._readium_blockedEvents.shift();switch(t[0]){case 0:Reflect.apply(t[1],t[2],t[3]);break;case 1:let n=t[1],r=t[2];e.removeEventListener(n.type,e._readium_eventBlocker,!0);let i=new Event(n.type,{bubbles:n.bubbles,cancelable:n.cancelable});r?r.dispatchEvent(i):e.dispatchEvent(i)}}}onMediaPlayEvent(){this.mediaPlayingCount++,this.comms?.send(`media_play`,this.mediaPlayingCount)}onMediaPauseEvent(){this.mediaPlayingCount>0&&this.mediaPlayingCount--,this.comms?.send(`media_pause`,this.mediaPlayingCount)}pauseAllMedia(e){let t=e.document.querySelectorAll(`audio,video`);for(let e=0;e<t.length;e++)t[e].pause()}mount(t,n){this.comms=n,t.addEventListener(`error`,this.wndOnErr,!1),Reflect.defineProperty(t.navigator,"epubReadingSystem",{value:{name:`readium-ts-toolkit`,version:`2.8.4`,hasFeature:(e,t=``)=>{switch(e){case`dom-manipulation`:return!0;case`layout-changes`:return!0;case`touch-events`:return!0;case`mouse-events`:return!0;case`keyboard-events`:return!0;case`spine-scripting`:return!0;case`embedded-web-content`:return!0;default:return!1}}},writable:!1}),`getAnimations`in t.document&&t.document.getAnimations().forEach(e=>{e.cancel(),this.allAnimations.add(e)}),n.register(`activate`,e.moduleName,(e,t)=>{this.allAnimations.forEach(e=>{e.cancel(),e.play()}),t(!0)}),n.register(`unfocus`,e.moduleName,(e,n)=>{this.pauseAllMedia(t),this.allAnimations.forEach(e=>e.pause()),n(!0)});let r=t.document.querySelectorAll(`audio,video`);for(let e=0;e<r.length;e++){let t=r[e];t.addEventListener(`play`,this.onMediaPlayEvent,{passive:!0}),t.addEventListener(`pause`,this.onMediaPauseEvent,{passive:!0})}return n.log(`Setup Mounted`),!0}unmount(e,t){return e.removeEventListener(`error`,this.wndOnErr),e.removeEventListener(`play`,this.onMediaPlayEvent),e.removeEventListener(`pause`,this.onMediaPauseEvent),this.allAnimations.forEach(e=>e.cancel()),this.allAnimations.clear(),t.log(`Setup Unmounted`),!0}};Fs.moduleName=`setup`;var Is=Fs,Ls=`readium-viewport`,Rs=class e extends Is{onViewportWidthChanged(e){let t=e.target;Ua(t,`--RS__viewportWidth`,`${t.innerWidth}px`)}mount(t,n){if(!super.mount(t,n))return!1;let r=t.document.createElement(`meta`);return r.dataset.readium=`true`,r.setAttribute(`name`,`viewport`),r.setAttribute(`id`,Ls),r.setAttribute(`content`,`width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, shrink-to-fit=no`),t.document.head.appendChild(r),t.addEventListener(`orientationchange`,this.onViewportWidthChanged),t.addEventListener(`resize`,this.onViewportWidthChanged),this.onViewportWidthChanged({target:t}),n.register(`get_properties`,e.moduleName,(e,n)=>{Ba(t),n(!0)}),n.register(`update_properties`,e.moduleName,(e,n)=>{e[`--RS__viewportWidth`]=`${t.innerWidth}px`,Va(t,e),n(!0)}),n.register(`set_property`,e.moduleName,(e,n)=>{let r=e;Ua(t,r[0],r[1]),n(!0)}),n.register(`remove_property`,e.moduleName,(e,n)=>{Wa(t,e),n(!0)}),n.register(`activate`,e.moduleName,(e,n)=>{this.unblock(t),n(!0)}),n.log(`ReflowableSetup Mounted`),!0}unmount(t,n){return n.unregisterAll(e.moduleName),t.document.head.querySelector(`#${Ls}`)?.remove(),t.removeEventListener(`orientationchange`,this.onViewportWidthChanged),n.log(`ReflowableSetup Unmounted`),super.unmount(t,n)}};Rs.moduleName=`reflowable_setup`;var zs=Rs,Bs=`readium-fixed-style`,Vs=class e extends Is{mount(t,n){if(!super.mount(t,n))return!1;t.navigator.epubReadingSystem&&(t.navigator.epubReadingSystem.layoutStyle=`paginated`);let r=t.document.createElement(`style`);return r.id=Bs,r.dataset.readium=`true`,r.textContent=`
        html, body {
            text-size-adjust: none;
            -ms-text-size-adjust: none;
            -webkit-text-size-adjust: none;
            -moz-text-size-adjust: none;

            /* Fight Safari pinches */
            touch-action: none !important;
            min-height: 100%;

            /*cursor: var() TODO*/
        }`,t.document.head.appendChild(r),n.register(`set_property`,e.moduleName,(e,n)=>{let r=e;Ua(t,r[0],r[1]),n(!0)}),n.register(`remove_property`,e.moduleName,(e,n)=>{Wa(t,e),n(!0)}),n.register(`first_visible_locator`,e.moduleName,(e,t)=>t(!1)),n.register(`unfocus`,e.moduleName,(e,n)=>{H(t),n(!0)}),n.register([`focus`,`go_next`,`go_prev`,`go_id`,`go_end`,`go_start`,`go_text`,`go_progression`],e.moduleName,(e,t)=>t(!0)),n.register(`activate`,e.moduleName,(e,n)=>{this.unblock(t),n(!0)}),n.log(`FixedSetup Mounted`),!0}unmount(t,n){return n.unregisterAll(e.moduleName),t.document.getElementById(Bs)?.remove(),n.log(`FixedSetup Unmounted`),super.unmount(t,n)}};Vs.moduleName=`fixed_setup`;var Hs=Vs;function Us(e,t){let n=t.map(e=>e.toUpperCase()),r=[],i=e.commonAncestorContainer,a=i.nodeType===Node.TEXT_NODE?i.parentNode:i,o=e.startContainer.ownerDocument.createTreeWalker(a,NodeFilter.SHOW_TEXT),s=o.nextNode();for(;s;){if(e.intersectsNode(s)){let t=s.parentNode,i=!1;for(;t;){if(t.nodeType===Node.ELEMENT_NODE&&n.includes(t.tagName.toUpperCase())){i=!0;break}t=t.parentNode}if(!i){let t=e.cloneRange();t.selectNode(s),t.compareBoundaryPoints(Range.START_TO_START,e)<0&&t.setStart(e.startContainer,e.startOffset),t.compareBoundaryPoints(Range.END_TO_END,e)>0&&t.setEnd(e.endContainer,e.endOffset);for(let e of t.getClientRects())r.push({left:e.left,right:e.right,top:e.top,bottom:e.bottom,width:e.width,height:e.height})}}s=o.nextNode()}return r}function Ws(e,t,n=!1,r=0){let i;if(Array.isArray(e))i=e;else{let t=e.getClientRects();t.length||e.commonAncestorContainer.nodeType===Node.ELEMENT_NODE&&(t=e.commonAncestorContainer.getClientRects()),i=[];for(let e of t)i.push({bottom:e.bottom,height:e.height,left:e.left,right:e.right,top:e.top,width:e.width})}if(r)for(let e of i)e.left-=r,e.top-=r,e.right+=r,e.bottom+=r,e.width+=r*2,e.height+=r*2;let a=Xs(qs(Gs(i,1,t,n),1));for(let e=a.length-1;e>=0;e--){let t=a[e];if(!(t.width*t.height>4)){if(a.length>1)a.splice(e,1);else break}}return a}function Gs(e,t,n,r=!1){for(let i=0;i<e.length;i++)for(let a=i+1;a<e.length;a++){let o=e[i],s=e[a];if(o===s)continue;let c=U(o.top,s.top,t)&&U(o.bottom,s.bottom,t),l=U(o.left,s.left,t)&&U(o.right,s.right,t);if((l&&!n&&!r||c&&!l)&&$s(o,s,t)){let i=e.filter(e=>e!==o&&e!==s),a=Ks(o,s);return i.push(a),Gs(i,t,n,r)}}return e}function Ks(e,t){let n=Math.min(e.left,t.left),r=Math.max(e.right,t.right),i=Math.min(e.top,t.top),a=Math.max(e.bottom,t.bottom);return{bottom:a,height:a-i,left:n,right:r,top:i,width:r-n}}function qs(e,t){let n=new Set(e);for(let r of e)if(!(r.width>1&&r.height>1))n.delete(r);else for(let i of e)if(r!==i&&n.has(i)&&Js(i,r,t)){n.delete(r);break}return Array.from(n)}function Js(e,t,n){return Ys(e,t.left,t.top,n)&&Ys(e,t.right,t.top,n)&&Ys(e,t.left,t.bottom,n)&&Ys(e,t.right,t.bottom,n)}function Ys(e,t,n,r){return(e.left<t||U(e.left,t,r))&&(e.right>t||U(e.right,t,r))&&(e.top<n||U(e.top,n,r))&&(e.bottom>n||U(e.bottom,n,r))}function Xs(e){for(let t=0;t<e.length;t++)for(let n=t+1;n<e.length;n++){let r=e[t],i=e[n];if(r!==i&&$s(r,i,-1)){let t=[],n,a=Zs(r,i);if(a.length===1)t=a,n=r;else{let e=Zs(i,r);a.length<e.length?(t=a,n=r):(t=e,n=i)}let o=e.filter(e=>e!==n);return Array.prototype.push.apply(o,t),Xs(o)}}return e}function Zs(e,t){let n=Qs(t,e);if(n.height===0||n.width===0)return[e];let r=[];{let t={bottom:e.bottom,height:0,left:e.left,right:n.left,top:e.top,width:0};t.width=t.right-t.left,t.height=t.bottom-t.top,t.height!==0&&t.width!==0&&r.push(t)}{let t={bottom:n.top,height:0,left:n.left,right:n.right,top:e.top,width:0};t.width=t.right-t.left,t.height=t.bottom-t.top,t.height!==0&&t.width!==0&&r.push(t)}{let t={bottom:e.bottom,height:0,left:n.left,right:n.right,top:n.bottom,width:0};t.width=t.right-t.left,t.height=t.bottom-t.top,t.height!==0&&t.width!==0&&r.push(t)}{let t={bottom:e.bottom,height:0,left:n.right,right:e.right,top:e.top,width:0};t.width=t.right-t.left,t.height=t.bottom-t.top,t.height!==0&&t.width!==0&&r.push(t)}return r}function Qs(e,t){let n=Math.max(e.left,t.left),r=Math.min(e.right,t.right),i=Math.max(e.top,t.top),a=Math.min(e.bottom,t.bottom);return{bottom:a,height:Math.max(0,a-i),left:n,right:r,top:i,width:Math.max(0,r-n)}}function $s(e,t,n){return(e.left<t.right||n>=0&&U(e.left,t.right,n))&&(t.left<e.right||n>=0&&U(t.left,e.right,n))&&(e.top<t.bottom||n>=0&&U(e.top,t.bottom,n))&&(t.top<e.bottom||n>=0&&U(t.top,e.bottom,n))}function U(e,t,n){return Math.abs(e-t)<=n}var ec=`div.span.p.br.hr.b.i.em.strong.s.u.mark.small.sub.sup.abbr.cite.code.data.dfn.kbd.q.samp.time.var.blockquote.pre.svg.g.path.circle.ellipse.rect.line.polygon.polyline.text.tspan.defs.use`.split(`.`),tc=/^on/i,nc=new Set([`href`,`src`,`action`,`formaction`,`xlink:href`]),rc=/^\s*(javascript|data):/i;function ic(e,t){let n=e.document.createElement(`div`);if(`Sanitizer`in e&&typeof n.setHTML==`function`)try{let r=new e.Sanitizer({allowElements:ec});return n.setHTML(t,{sanitizer:r}),n.firstElementChild}catch{}let r=e.document.implementation.createHTMLDocument(``);for(r.body.innerHTML=t,ac(r.body,new Set(ec));r.body.firstChild;)n.appendChild(e.document.adoptNode(r.body.firstChild));return n.firstElementChild}function ac(e,t){let n=Array.from(e.querySelectorAll(`*`)).reverse();for(let e of n)if(!t.has(e.localName))e.replaceWith(...Array.from(e.childNodes));else for(let{name:t,value:n}of Array.from(e.attributes))(tc.test(t)||nc.has(t)&&rc.test(n))&&e.removeAttribute(t)}function oc(e){switch(e){case W.Mask:return`rgba(255, 255, 255, 0.5)`;case W.Highlight:case W.HighlightUnderline:return`#FFFF00`;default:return`#FF0000`}}var W={Highlight:`highlight`,HighlightUnderline:`highlightUnderline`,Underline:`underline`,Strikethrough:`strikethrough`,Outline:`outline`,TextColor:`textColor`,Mask:`mask`,Template:`template`},sc=(e=>(e.Wrap=`wrap`,e.Viewport=`viewport`,e.Bounds=`bounds`,e.Page=`page`,e))(sc||{}),cc=(e=>(e.Boxes=`boxes`,e.Bounds=`bounds`,e))(cc||{}),lc=()=>`Highlight`in window,uc=[`IMG`,`IMAGE`,`AUDIO`,`VIDEO`,`SVG`],dc=new Set([`SUP`,`SUB`,`SMALL`,`CODE`]),fc=class{constructor(e,t,n,r){this.wnd=e,this.comms=t,this.id=n,this.name=r,this.items=[],this.lastItemId=0,this.container=void 0,this._activatable=!1,this._hoverable=!1,this.hoveredItem=void 0,this.experimentalHighlights=!1,this._tintSubKeys=new Map,this._subKeyCounter=0,this.pendingWebkitReflow=null,this.maskSvg=void 0,this.shadowHost=void 0,this.shadowRoot=void 0,this.currentRender=0,lc()&&(this.experimentalHighlights=!0,this.notTextFlag=new Map),this.activationHandler=this.handleActivation.bind(this),this.wnd.document.addEventListener(`pointerup`,this.activationHandler),this.hoverHandler=this.handleHover.bind(this),this.wnd.document.addEventListener(`pointermove`,this.hoverHandler)}get activatable(){return this._activatable}set activatable(e){this._activatable=e}get hoverable(){return this._hoverable}get hasOverlayItems(){return!this.experimentalHighlights||(this.notTextFlag?.size??0)>0}set hoverable(e){if(this._hoverable=e,!e&&this.hoveredItem){let e=this.hoveredItem.range.getBoundingClientRect(),t=this.wnd.devicePixelRatio;this.comms.send(`decoration_pointer_leave`,{decorationId:this.hoveredItem.decoration.id,group:this.name,rect:{top:e.top*t,left:e.left*t,width:e.width*t,height:e.height*t}}),this.hoveredItem=void 0}}add(e){let t=`${this.id}-${this.lastItemId++}`,n=as(this.wnd.document,e.locator);if(!n){this.comms.log(`Can't locate DOM range for decoration`,e);return}let r=n.commonAncestorContainer;if(r.nodeType!==Node.TEXT_NODE&&this.experimentalHighlights&&(uc.includes(r.nodeName.toUpperCase())&&this.notTextFlag?.set(t,!0),n.cloneContents().querySelector(uc.join(`, `).toLowerCase())&&this.notTextFlag?.set(t,!0),(r.textContent?.trim()||``).length===0&&this.notTextFlag?.set(t,!0)),this.experimentalHighlights&&!this.notTextFlag?.has(t)){let e=e=>{for(;e&&e.nodeType===Node.ELEMENT_NODE;){if(e.namespaceURI?.includes(`svg`))return!0;e=e.parentNode}return!1};(e(n.startContainer)||e(n.endContainer))&&this.notTextFlag?.set(t,!0)}if(this.experimentalHighlights){let{type:n}=e.style,{layout:r,width:i,expand:a}=e.style;n!==W.TextColor&&(n===W.Outline||n===W.Template||n===W.Mask||r!==void 0&&r!==`boxes`||i!==void 0&&i!==`wrap`||a)&&this.notTextFlag?.set(t,!0)}let i={decoration:e,id:t,range:n,hitRects:[],clickableElements:void 0,container:void 0};this.items.push(i),this.layout(i),i.hitRects=this.clientRectsToDocCoords(Ws(i.range,!1,!1,(i.decoration.style.expand??0)+this.hitGap())),this.renderLayout([i])}remove(e){let t=this.items.findIndex(t=>t.decoration.id===e);if(t<0)return;let n=this.items[t],r=n.decoration.style?.type===W.Mask;if(this.items.splice(t,1),n.clickableElements=void 0,n.container&&=(n.container.remove(),void 0),this.experimentalHighlights&&!this.notTextFlag?.has(n.id)&&n.highlightSubKey){let e=this.wnd.CSS.highlights;e.get(n.highlightSubKey)?.delete(n.range),this.items.some(e=>e.highlightSubKey===n.highlightSubKey)||e.delete(n.highlightSubKey);let t=this.wnd.document.getElementById(`${this.id}-style`);t&&this._rebuildHighlightStylesheet(t),this.scheduleWebkitRepaintFix([n])}this.notTextFlag?.delete(n.id),this.hoveredItem===n&&(this.hoveredItem=void 0),r&&this.updateSharedMask()}update(e){this.remove(e.id),this.add(e)}clear(){this.experimentalHighlights&&this.scheduleWebkitRepaintFix(this.items),this.clearContainer(),this.items.length=0,this.notTextFlag?.clear(),this.hoveredItem=void 0,this.maskSvg&&=(this.maskSvg.remove(),void 0),this.shadowHost&&(this.shadowHost.remove(),this.shadowHost=void 0,this.shadowRoot=void 0)}destroy(){this.clear(),this.wnd.document.removeEventListener(`pointerup`,this.activationHandler),this.wnd.document.removeEventListener(`pointermove`,this.hoverHandler)}isWebkitRepaintProne(e){let t=this.wnd.getComputedStyle(e);if(dc.has(e.tagName.toUpperCase())||t.display===`inline-block`||t.verticalAlign!==`baseline`)return!0;let n=e.parentElement?this.wnd.getComputedStyle(e.parentElement):null;return!!n&&parseFloat(t.fontSize)!==parseFloat(n.fontSize)}findWebkitRepaintProneElement(e){let t=e.startContainer.nodeType===Node.ELEMENT_NODE?e.startContainer:e.startContainer.parentElement;for(;t;){if(this.isWebkitRepaintProne(t))return t;if(this.wnd.getComputedStyle(t).display!==`inline`)break;t=t.parentElement}let n=e.commonAncestorContainer,r=n.nodeType===Node.ELEMENT_NODE?n:n.parentElement;if(!r)return null;let i=this.wnd.document.createTreeWalker(r,NodeFilter.SHOW_ELEMENT,t=>e.intersectsNode(t)?NodeFilter.FILTER_ACCEPT:NodeFilter.FILTER_REJECT);for(let e=i.nextNode();e;e=i.nextNode())if(this.isWebkitRepaintProne(e))return e;return null}forceWebkitBlockReflow(e){let t=e;for(;t;){let e=this.wnd.getComputedStyle(t).display;if(e!==`inline`&&e!==`inline-block`)break;t=t.parentElement}if(!t||!t.isConnected)return;let n=t,r=n.style.getPropertyValue(`transform`),i=n.style.getPropertyPriority(`transform`);n.style.setProperty(`transform`,`translateZ(0.001px)`,`important`),n.offsetHeight,n.style.setProperty(`transform`,`translateZ(0px)`,`important`),n.offsetHeight,r?n.style.setProperty(`transform`,r,i):n.style.removeProperty(`transform`)}scheduleWebkitRepaintFix(e){if(B.UA.WebKit)for(let t of e){if(this.notTextFlag?.has(t.id)||!t.highlightSubKey)continue;let e=this.findWebkitRepaintProneElement(t.range);e&&this.queueWebkitReflow(e)}}queueWebkitReflow(e){this.pendingWebkitReflow||(this.pendingWebkitReflow=new Set,this.wnd.requestAnimationFrame(()=>{let e=this.pendingWebkitReflow;this.pendingWebkitReflow=null,e?.forEach(e=>this.forceWebkitBlockReflow(e))})),this.pendingWebkitReflow.add(e)}clientRectsToDocCoords(e,t=ja(this.wnd)){let n=t.xDocOffset,r=t.yDocOffset;return n===0&&r===0?e:e.map(e=>({left:e.left+n,top:e.top+r,right:e.right+n,bottom:e.bottom+r,width:e.width,height:e.height}))}pointerToDocCoords(e){let t=ja(this.wnd);return{docX:e.clientX+t.xDocOffset,docY:e.clientY+t.yDocOffset}}effectiveZoom(){if(!B.UA.Blink)return 1;let e=parseFloat(this.wnd.getComputedStyle(this.wnd.document.documentElement).zoom),t=parseFloat(this.wnd.getComputedStyle(this.wnd.document.body).zoom);return(e||1)*(t||1)}hitGap(){return 2*this.effectiveZoom()}handleActivation(e){if(!this._activatable)return;let{docX:t,docY:n}=this.pointerToDocCoords(e),r=this.wnd.devicePixelRatio;for(let i of this.items){let a;if(i.decoration.style.type===W.Template)for(let t of i.clickableElements??[]){let n=t.getBoundingClientRect();if(Ys(n,e.clientX,e.clientY,0)){a=n;break}}else for(let e of i.hitRects)if(Ys(e,t,n,0)){a=i.range.getBoundingClientRect();break}if(a){this.comms.send(`decoration_activated`,{decorationId:i.decoration.id,group:this.name,rect:{top:a.top*r,left:a.left*r,width:a.width*r,height:a.height*r},point:{x:e.clientX*r,y:e.clientY*r}});return}}}handleHover(e){if(!this._hoverable)return;let{docX:t,docY:n}=this.pointerToDocCoords(e),r=this.wnd.devicePixelRatio,i,a;for(let r of this.items){if(r.decoration.style.type===W.Template)for(let t of r.clickableElements??[]){let n=t.getBoundingClientRect();if(Ys(n,e.clientX,e.clientY,0)){i=r,a=n;break}}else for(let e of r.hitRects)if(Ys(e,t,n,0)){i=r,a=r.range.getBoundingClientRect();break}if(i)break}if(i!==this.hoveredItem){if(this.hoveredItem){let t=this.hoveredItem.range.commonAncestorContainer.isConnected?this.hoveredItem.range.getBoundingClientRect():null;this.comms.send(`decoration_pointer_leave`,{decorationId:this.hoveredItem.decoration.id,group:this.name,rect:t?{top:t.top*r,left:t.left*r,width:t.width*r,height:t.height*r}:void 0,point:{x:e.clientX*r,y:e.clientY*r}})}this.hoveredItem=i,i&&a&&this.comms.send(`decoration_pointer_enter`,{decorationId:i.decoration.id,group:this.name,rect:{top:a.top*r,left:a.left*r,width:a.width*r,height:a.height*r},point:{x:e.clientX*r,y:e.clientY*r}})}}requestLayout(){this.wnd.cancelAnimationFrame(this.currentRender),this.clearContainer(),this.wnd.document.fonts.ready.then(()=>{this.currentRender=this.wnd.requestAnimationFrame(()=>{this.items.forEach(e=>{this.layout(e),e.hitRects=this.clientRectsToDocCoords(Ws(e.range,!1,!1,(e.decoration.style.expand??0)+this.hitGap()))}),this.renderLayout(this.items),this.updateSharedMask()})})}repositionOverlays(){let e=!1,t=[],n=ja(this.wnd);this.items.forEach(r=>{if(!this.experimentalHighlights||this.notTextFlag?.has(r.id)){if(r.decoration.style?.type===W.Mask){e=!0;return}this.repositionItem(r,n)||(r.container?.remove(),this.layout(r),t.push(r)),r.hitRects=this.clientRectsToDocCoords(Ws(r.range,!1,!1,(r.decoration.style.expand??0)+this.hitGap()),n)}}),t.length&&this.renderLayout(t),e&&this.updateSharedMask()}experimentalLayout(e){let t=this.requireContainer(!0),n=this.wnd.CSS.highlights,r=e.decoration.style,i=r.type??W.Highlight,a=r.tint??oc(i),o=r.width,s=r.layout,c=this._getSubKey(i,a);e.highlightSubKey&&(n.get(e.highlightSubKey)?.delete(e.range),e.highlightSubKey!==c&&!this.items.some(t=>t!==e&&t.highlightSubKey===e.highlightSubKey)&&n.delete(e.highlightSubKey)),e.highlightSubKey=c;let l;n.has(c)?l=n.get(c):(l=new this.wnd.Highlight,n.set(c,l));let u=(e,t)=>this.wnd.document.caretPositionFromPoint?.(e,t)??null;if(i===W.TextColor&&(s===`bounds`||o===`bounds`||o===`page`)){let t=ja(this.wnd);if(t.isVertical)console.warn(`Vertical writing detected: caretPositionFromPoint has known bugs, falling back to original range`),l.add(e.range);else{let n=e.range.getBoundingClientRect(),r,i;o===`page`?(r=Math.floor(t.inlineStart(n)/t.pageInlineSize)*t.pageInlineSize,i=t.pageInlineSize):(r=t.inlineStart(n),i=t.inlineSize(n));let a=u(r,t.blockStart(n)+1),s=u(r+i,t.blockStart(n)+t.blockSize(n)-1);if(a&&s){let t=this.wnd.document.createRange();t.setStart(a.offsetNode,a.offset),t.setEnd(s.offsetNode,s.offset),l.add(t),e.range=t}else l.add(e.range)}}else l.add(e.range);let d=this.getBackgroundColor(),f=r.enforceContrast===!1?a:lo(a,d),p;switch(i){case W.Underline:p=`::highlight(${c}) {
                    text-decoration: underline;
                    text-decoration-color: ${f};
                    text-decoration-thickness: 0.1em;
                }`;break;case W.Strikethrough:p=`::highlight(${c}) {
                    text-decoration: line-through;
                    text-decoration-color: ${f};
                    text-decoration-thickness: 0.1em;
                }`;break;case W.Outline:p=`::highlight(${c}) {
                    outline: 2px solid ${f};
                    outline-offset: 1px;
                }`;break;case W.TextColor:p=`::highlight(${c}) {
                    color: ${f};
                }`;break;case W.HighlightUnderline:{let{r:e,g:t,b:n}=eo(f),r=`rgba(${e}, ${t}, ${n}, 0.3)`;p=`::highlight(${c}) {
                    color: ${ao(f,d)};
                    background-color: ${r};
                    text-decoration: underline;
                    text-decoration-color: ${f};
                    text-decoration-thickness: 0.1em;
                }`;break}case W.Highlight:default:p=`::highlight(${c}) {
                    color: ${ao(f,d)};
                    background-color: ${f};
                }`}e.highlightCSS=p,this._rebuildHighlightStylesheet(t)}_getSubKey(e,t){let n=`${e}::${t}`,r=this._tintSubKeys.get(n);return r||(r=`${this.id}--${this._subKeyCounter++}`,this._tintSubKeys.set(n,r)),r}_rebuildHighlightStylesheet(e){let t=new Set,n=[];for(let e of this.items)e.highlightSubKey&&e.highlightCSS&&!t.has(e.highlightSubKey)&&(t.add(e.highlightSubKey),n.push(e.highlightCSS));e.innerHTML=n.join(`
`)}positionElement(e,t,n,r,i,a,o=0){let s=e.decoration?.style?.width,c=i;switch(s){case`viewport`:{let e=Math.floor(t.inlineStart(c)/t.viewportInlineSize)*t.viewportInlineSize;t.applyPosition(r,e+t.inlineScrollOffset+o,t.blockStart(c)+t.blockScrollOffset,t.viewportInlineSize-2*o,t.blockSize(c),n);break}case`page`:{let e=Math.floor(t.inlineStart(c)/t.pageInlineSize)*t.pageInlineSize;t.applyPosition(r,e+t.inlineScrollOffset+o,t.blockStart(c)+t.blockScrollOffset,t.pageInlineSize-2*o,t.blockSize(c),n);break}case`bounds`:t.applyPosition(r,t.inlineStart(a)+t.inlineScrollOffset,t.blockStart(c)+t.blockScrollOffset,t.inlineSize(a),t.blockSize(c),n);break;default:t.applyPosition(r,t.inlineStart(c)+t.inlineScrollOffset,t.blockStart(c)+t.blockScrollOffset,t.inlineSize(c),t.blockSize(c),n)}}computeOverlayRects(e,t,n,r){if(e.decoration?.style?.layout===`bounds`)return[r?{left:n.left-r,right:n.right+r,top:n.top-r,bottom:n.bottom+r,width:n.width+r*2,height:n.height+r*2}:n];let i=e.decoration.style.type,a=i===W.Underline||i===W.Strikethrough,o=i===W.Strikethrough,s=Ws(a?Us(e.range,[`rt`,`rp`]):e.range,!0,t.isVertical,a?0:r);return s=s.sort((e,n)=>t.isVertical?(t.isVertLR?1:-1)*(e.left-n.left):e.top-n.top),s.map(e=>{let n=e;if(o){let r=t.blockSize(e)*.1,i=t.blockStart(e)+t.blockSize(e)/2-r/2;n=t.isVertical?{left:i,right:i+r,top:e.top,bottom:e.bottom,width:r,height:e.height}:{top:i,bottom:i+r,left:e.left,right:e.right,height:r,width:e.width}}return r&&a&&(n=t.isVertical?{...n,top:n.top-r,bottom:n.bottom+r,height:n.height+r*2}:{...n,left:n.left-r,right:n.right+r,width:n.width+r*2}),n})}repositionItem(e,t){if(!e.container)return!0;let n=e.decoration.style;if(n.type!==W.Template){let e=n.type??W.Highlight;if(e===W.TextColor||e===W.Mask)return!0}let r=1/this.effectiveZoom(),i=n.expand??0,a=e.range.getBoundingClientRect(),o=(()=>{if(n.type!==W.Outline)return 0;let e=n.width;return e===`page`||e===`viewport`?3:0})(),s=this.computeOverlayRects(e,t,a,i),c=Array.from(e.container.children);return c.length===s.length&&(c.forEach((n,i)=>this.positionElement(e,t,r,n,s[i],a,o)),!0)}layout(e){if(this.experimentalHighlights&&!this.notTextFlag?.has(e.id))return this.experimentalLayout(e);let t=this.wnd.document.createElement(`div`);t.setAttribute(`id`,e.id),t.dataset.highlightId=e.decoration.id,t.style.setProperty(`pointer-events`,`none`);let n=ja(this.wnd),r=1/this.effectiveZoom(),i=e.decoration.style.expand??0,a=e.range.getBoundingClientRect(),o=e.decoration.style,s=(()=>{if(o.type!==W.Outline)return 0;let e=o.width;return e===`page`||e===`viewport`?3:0})(),c;if(o.type===W.Template){o.stylesheet&&this.injectCustomStylesheet(o.stylesheet);let n=ic(this.wnd,o.element);if(!n){e.container=t,e.clickableElements=[];return}n.style.setProperty(`pointer-events`,`none`),c=n}else{let r=o,i=r.type??W.Highlight,a=r.tint??oc(i);if(i===W.TextColor){e.container=t,e.clickableElements=[];return}if(i===W.Mask){e.container=t,e.clickableElements=[],this.updateSharedMask();return}let s=this.getCurrentDarkMode(),l=this.getBackgroundColor(),u=r.enforceContrast!==!1,d=(()=>{switch(i){case W.Underline:{let e=u?lo(a,l):a,t=r.layout===`bounds`,[i,o]=n.isVertical?[`border-right`,`border-left`]:[`border-bottom`,`border-top`];return[t?`${o}: 0.1em solid ${e} !important`:null,`${i}: 0.1em solid ${e} !important`,`background-color: transparent !important`,`box-sizing: border-box !important`].filter(Boolean).join(`; `)}case W.Strikethrough:{let e=u?lo(a,l):a;return r.layout===`bounds`?[`background: repeating-linear-gradient(-45deg, transparent, transparent 19px, ${e} 19px, ${e} 20px) !important`,`background-color: transparent !important`,`box-sizing: border-box !important`].join(`; `):[`background-color: ${e} !important`,`box-sizing: border-box !important`].join(`; `)}case W.Outline:return[`outline: 2px solid ${u?lo(a,l):a} !important`,`outline-offset: 1px !important`,`background-color: transparent !important`,`box-sizing: border-box !important`].join(`; `);case W.HighlightUnderline:{let e=u?lo(a,l):a,{r:t,g:i,b:o}=eo(e),s=`rgba(${t}, ${i}, ${o}, 0.3)`,c=r.layout===`bounds`,[d,f]=n.isVertical?[`border-right`,`border-left`]:[`border-bottom`,`border-top`];return[`background-color: ${s} !important`,c?`${f}: 0.1em solid ${e} !important`:null,`${d}: 0.1em solid ${e} !important`,`box-sizing: border-box !important`].filter(Boolean).join(`; `)}case W.Highlight:default:return[`background-color: ${u?lo(a,l):a} !important`,`mix-blend-mode: ${s?`exclusion`:`multiply`} !important`,`opacity: 1 !important`,`box-sizing: border-box !important`,`transform: translateZ(0) !important`].join(`; `)}})(),f=this.wnd.document.createElement(`template`);f.innerHTML=`<div data-readium="true" class="readium-${i}" style="${d}"></div>`.trim(),c=f.content.firstElementChild}let l=this.computeOverlayRects(e,n,a,i);for(let i of l){let o=c.cloneNode(!0);o.style.setProperty(`pointer-events`,`none`),this.positionElement(e,n,r,o,i,a,s),t.append(o)}e.container=t,e.clickableElements=Array.from(t.querySelectorAll(`[data-activable='1']`)),e.clickableElements.length||(e.clickableElements=Array.from(t.children))}renderLayout(e){this.wnd.cancelAnimationFrame(this.currentRender),this.currentRender=this.wnd.requestAnimationFrame(()=>{e=e.filter(e=>!this.experimentalHighlights||!!this.notTextFlag?.has(e.id)),e&&e.length!==0&&this.requireContainer().append(...e.map(e=>e.container).filter(e=>!!e))})}requireContainer(e=!1){if(e){let e;return this.wnd.document.getElementById(`${this.id}-style`)?e=this.wnd.document.getElementById(`${this.id}-style`):(e=this.wnd.document.createElement(`style`),e.dataset.readium=`true`,e.id=`${this.id}-style`,this.wnd.document.head.appendChild(e)),e}return this.container||(this.shadowRoot||=(this.shadowHost=this.wnd.document.createElement(`div`),this.shadowHost.style.cssText=`position:absolute;top:0;left:0;width:100%;height:100%;pointer-events:none`,this.wnd.document.body.appendChild(this.shadowHost),this.shadowHost.attachShadow({mode:`open`})),this.container=this.wnd.document.createElement(`div`),this.container.setAttribute(`id`,this.id),this.container.dataset.group=this.name,this.container.dataset.readium=`true`,this.container.style.setProperty(`pointer-events`,`none`),this.container.style.display=`contents`,this.shadowRoot.appendChild(this.container)),this.container}getCurrentDarkMode(){return Ha(this.wnd,`--USER__appearance`)===`readium-night-on`||io(this.getBackgroundColor())}getBackgroundColor(){return Ha(this.wnd,`--USER__backgroundColor`)||this.wnd.getComputedStyle(this.wnd.document.documentElement).getPropertyValue(`background-color`)}updateSharedMask(){let e=this.items.filter(e=>e.decoration.style?.type===W.Mask);if(e.length===0){this.maskSvg&&=(this.maskSvg.remove(),void 0),this.shadowHost&&!this.container&&(this.shadowHost.remove(),this.shadowRoot=void 0,this.shadowHost=void 0);return}let t=ja(this.wnd),n=1/this.effectiveZoom(),r=this.wnd.document.documentElement,i=r.scrollWidth,a=r.scrollHeight,o=[];for(let n of e){let e=n.decoration.style,r=e.layout??`boxes`,i=e.width??`wrap`,a=e.expand??0,s=n.range.getBoundingClientRect(),c=r===`bounds`?[a?{left:s.left-a,top:s.top-a,right:s.right+a,bottom:s.bottom+a,width:s.width+a*2,height:s.height+a*2}:s]:Ws(n.range,!1,!1,a);for(let e of c){let n;switch(i){case`viewport`:{let r=Math.floor(t.inlineStart(e)/t.viewportInlineSize)*t.viewportInlineSize;n=t.toRect(r,t.blockStart(e),t.viewportInlineSize,t.blockSize(e));break}case`page`:{let r=Math.floor(t.inlineStart(e)/t.pageInlineSize)*t.pageInlineSize;n=t.toRect(r,t.blockStart(e),t.pageInlineSize,t.blockSize(e));break}case`bounds`:n=t.toRect(t.inlineStart(s),t.blockStart(e),t.inlineSize(s),t.blockSize(e));break;default:n=t.toRect(t.inlineStart(e),t.blockStart(e),t.inlineSize(e),t.blockSize(e))}o.push(n)}}let s=[`M0 0 H${i} V${a} H0 Z`,...o.map(e=>{let r=(e.left+t.xDocOffset)*n;return`M${r} ${(e.top+t.yDocOffset)*n} H${(e.right+t.xDocOffset)*n} V${(e.bottom+t.yDocOffset)*n} H${r} Z`})].join(` `),c=`http://www.w3.org/2000/svg`;if(!this.maskSvg){this.shadowRoot||=(this.shadowHost=this.wnd.document.createElement(`div`),this.shadowHost.style.cssText=`position:absolute;top:0;left:0;width:100%;height:100%;pointer-events:none`,this.wnd.document.body.appendChild(this.shadowHost),this.shadowHost.attachShadow({mode:`open`})),this.maskSvg=this.wnd.document.createElementNS(c,`svg`),this.maskSvg.style.cssText=`position:absolute;top:0;left:0;width:${i}px;height:${a}px;pointer-events:none;z-index:2147483647`,this.maskSvg.dataset.readium=`true`;let e=this.wnd.document.createElementNS(c,`defs`),t=this.wnd.document.createElementNS(c,`clipPath`),n=`${this.id}-mask-clip`;t.setAttribute(`id`,n),t.setAttribute(`clipPathUnits`,`userSpaceOnUse`);let r=this.wnd.document.createElementNS(c,`path`);r.setAttribute(`clip-rule`,`evenodd`),t.appendChild(r),e.appendChild(t),this.maskSvg.appendChild(e);let o=this.wnd.document.createElementNS(c,`rect`);o.setAttribute(`id`,`${this.id}-mask-rect`),o.setAttribute(`clip-path`,`url(#${n})`),o.style.pointerEvents=`none`,this.maskSvg.appendChild(o),this.shadowRoot.appendChild(this.maskSvg)}this.maskSvg.style.width=`${i}px`,this.maskSvg.style.height=`${a}px`;let l=this.maskSvg.querySelector(`path`);l&&l.setAttribute(`d`,s);let u=this.maskSvg.querySelector(`rect`);if(u){let t=e[0].decoration.style.tint,n=t??this.getBackgroundColor()??oc(W.Mask),r=t?`1`:`0.5`;u.setAttribute(`x`,`0`),u.setAttribute(`y`,`0`),u.setAttribute(`width`,String(i)),u.setAttribute(`height`,String(a)),u.setAttribute(`fill`,n),u.setAttribute(`fill-opacity`,r)}}injectCustomStylesheet(e){let t=`${this.id}-custom-style`,n=this.wnd.document.getElementById(t);n||(n=this.wnd.document.createElement(`style`),n.id=t,n.dataset.readium=`true`,this.wnd.document.head.appendChild(n)),n.innerHTML=e}clearContainer(){if(this.experimentalHighlights){let e=this.wnd.CSS.highlights;for(let t of this._tintSubKeys.values())e.delete(t);this._tintSubKeys.clear(),this._subKeyCounter=0}this.wnd.document.getElementById(`${this.id}-custom-style`)?.remove(),this.container&&=(this.container.remove(),void 0)}},pc=class e extends Ta{constructor(){super(...arguments),this.observedResizeTargets=new Map,this.resizeFrame=0,this.lastGroupId=0,this.groups=new Map,this.handleResizer=this.handleResize.bind(this),this.scrollScheduled=!1,this.handleScroller=this.handleScroll.bind(this)}cleanup(){this.groups.forEach(e=>e.destroy()),this.groups.clear(),this.observedResizeTargets.clear()}updateHighlightStyles(){this.groups.forEach(e=>{e.requestLayout()})}handleResize(){this.wnd.clearTimeout(this.resizeFrame),this.resizeFrame=this.wnd.setTimeout(()=>{this.groups.forEach(e=>e.requestLayout())},50)}handleScroll(){this.scrollScheduled||(this.scrollScheduled=!0,this.wnd.requestAnimationFrame(()=>{this.scrollScheduled=!1,this.groups.forEach(e=>{e.hasOverlayItems&&e.repositionOverlays()})}))}mount(t,n){return this.wnd=t,n.register(`decorate`,e.moduleName,(e,r)=>{let i=e;(i.action===`add`||i.action===`update`)&&i.decoration.locator&&(i.decoration.locator=j.deserialize(i.decoration.locator)),this.groups.has(i.group)||this.groups.set(i.group,new fc(t,n,`readium-decoration-${this.lastGroupId++}`,i.group));let a=this.groups.get(i.group);switch(i.action){case`add`:a?.add(i.decoration);break;case`remove`:a?.remove(i.decoration.id);break;case`clear`:a?.clear();break;case`update`:a?.update(i.decoration)}r(!0)}),n.register(`decoration_resize`,e.moduleName,(e,t)=>{let n=e;n.action===`watch`?this.addDecorationResizeTarget(n.selector):this.removeDecorationResizeTarget(n.selector),t(!0)}),n.register(`decoration_activatable`,e.moduleName,(e,t)=>{let n=e,r=this.groups.get(n.group);r&&(r.activatable=n.activatable),t(!0)}),n.register(`decoration_hoverable`,e.moduleName,(e,t)=>{let n=e,r=this.groups.get(n.group);r&&(r.hoverable=n.hoverable),t(!0)}),this.resizeObserver=new ResizeObserver(()=>t.requestAnimationFrame(()=>this.handleResize())),this.resizeObserver.observe(t.document.documentElement),t.addEventListener(`orientationchange`,this.handleResizer),t.addEventListener(`resize`,this.handleResizer),t.addEventListener(`scroll`,this.handleScroller,{passive:!0,capture:!0}),this.styleObserver=new MutationObserver(e=>{e.some(e=>e.type===`attributes`&&e.attributeName===`style`&&e.oldValue!==e.target.getAttribute(`style`))&&this.updateHighlightStyles()}),this.styleObserver.observe(t.document.documentElement,{attributes:!0,attributeFilter:[`style`],attributeOldValue:!0}),n.log(`Decorator Mounted`),!0}unmount(t,n){return t.removeEventListener(`orientationchange`,this.handleResizer),t.removeEventListener(`resize`,this.handleResizer),t.removeEventListener(`scroll`,this.handleScroller,{capture:!0}),n.unregisterAll(e.moduleName),this.resizeObserver.disconnect(),this.styleObserver.disconnect(),this.cleanup(),n.log(`Decorator Unmounted`),!0}addDecorationResizeTarget(e){let t=this.observedResizeTargets.get(e);t&&this.resizeObserver.unobserve(t);let n=this.wnd.document.querySelector(e);n?(this.resizeObserver.observe(n),this.observedResizeTargets.set(e,n)):this.observedResizeTargets.delete(e)}removeDecorationResizeTarget(e){let t=this.observedResizeTargets.get(e);t&&(this.resizeObserver.unobserve(t),this.observedResizeTargets.delete(e))}};pc.moduleName=`decorator`;var mc=pc,hc=class e extends Ta{wndOnErr(e){this.comms?.send(`error`,{message:e.message,filename:e.filename,lineno:e.lineno,colno:e.colno})}mount(t,n){return this.comms=n,t.addEventListener(`error`,this.wndOnErr,!1),n.register(`get_properties`,e.moduleName,(e,n)=>{Ba(t),n(!0)}),n.register(`update_properties`,e.moduleName,(e,n)=>{Va(t,e),n(!0)}),n.register(`set_property`,e.moduleName,(e,n)=>{let r=e;Ua(t,r[0],r[1]),n(!0)}),n.register(`remove_property`,e.moduleName,(e,n)=>{Wa(t,e),n(!0)}),n.register(`activate`,e.moduleName,(e,t)=>{t(!0)}),n.log(`WebPubSetup Mounted`),!0}unmount(t,n){return n.unregisterAll(e.moduleName),t.removeEventListener(`error`,this.wndOnErr),n.log(`WebPubSetup Unmounted`),!0}};hc.moduleName=`webpub_setup`;var gc=hc,_c=class e extends Ta{constructor(){super(...arguments),this.styleElement=null,this.beforePrintHandler=null,this.configApplied=!1}setupPrintProtection(e,t){if(!t.disable)return;let n=e.document.createElement(`style`);n.textContent=`
            @media print {
                body * {
                    display: none !important;
                }
                body::after {
                    content: "${t.watermark||`Printing has been disabled`}";
                    font-size: 200%;
                    display: block;
                    text-align: center;
                    margin-top: 50vh;
                    transform: translateY(-50%);
                }
            }
        `,e.document.head.appendChild(n),this.styleElement=n,this.beforePrintHandler=e=>(e.preventDefault(),!1),e.addEventListener(`beforeprint`,this.beforePrintHandler)}registerPrintHandlers(){this.comms?.register(`print_protection`,e.moduleName,e=>{let t=e;return this.configApplied||(this.configApplied=!0,this.setupPrintProtection(this.wnd,t),this.comms?.log(`Print protection configuration applied`)),!0})}mount(e,t){return this.wnd=e,this.comms=t,this.registerPrintHandlers(),!0}unmount(t,n){return this.beforePrintHandler&&=(t.removeEventListener(`beforeprint`,this.beforePrintHandler),null),this.styleElement?.parentNode&&(this.styleElement.parentNode.removeChild(this.styleElement),this.styleElement=null),this.comms?.unregisterAll(e.moduleName),this.configApplied=!1,!0}};_c.moduleName=`print_protection`;var vc=_c,yc=`readium-cjk-vertical-snapper-style`,bc=class e extends z{constructor(){super(...arguments),this.patternAnalyzer=null,this.lastScrollTime=0,this.isScrollProtectionEnabled=!1,this.initialScrollHandled=!1,this.isScrolling=!1,this.lastScrollLeft=0,this.isResizing=!1,this.resizeDebounce=null,this.verticalLR=!1,this.handleScroll=e=>{if(this.comms.ready&&!this.isResizing){if(!this.initialScrollHandled){this.lastScrollLeft=Math.abs(this.doc().scrollLeft),this.initialScrollHandled=!0,this.reportProgress();return}this.isScrolling||(this.isScrolling=!0,this.wnd.requestAnimationFrame(()=>{this.reportProgress();let t=Math.abs(this.doc().scrollLeft),n=t-this.lastScrollLeft;if(this.lastScrollLeft=t,this.isScrollProtectionEnabled&&Math.abs(n)>5){let t=Date.now(),r=t-(this.lastScrollTime||t);if(this.patternAnalyzer&&this.patternAnalyzer.analyze(n>0?`down`:`up`,Math.abs(n),r)){let t=e.target&&`tagName`in e.target?{tagName:e.target.tagName}:null;this.comms?.send(`content_protection`,{type:`suspicious_scrolling`,timestamp:Date.now(),scrollDelta:n,scrollDirection:n>0?`left`:`right`,targetElement:t})}this.lastScrollTime=t}this.comms.send(`scroll`,n),this.isScrolling=!1}))}}}doc(){return this.wnd.document.scrollingElement}scrollable(){return Math.max(0,this.doc().scrollWidth-this.wnd.innerWidth)}hasScrolledPast(e){let t=e.getBoundingClientRect(),n=this.wnd.innerWidth/2,r=this.wnd.innerWidth*z.CENTER_TOLERANCE;return this.verticalLR?t.right<=n+r:t.left>=n-r}inCenterBand(e){let t=e.getBoundingClientRect(),n=this.wnd.innerWidth/2,r=this.wnd.innerWidth*z.CENTER_TOLERANCE,i=n-r,a=n+r;return t.width===0?t.left<=a&&t.left>=i:Math.max(0,Math.min(t.right,a)-Math.max(t.left,i))/t.width>=z.CENTER_TOLERANCE}fragmentStart(e){return e.getBoundingClientRect().left+Math.abs(this.doc().scrollLeft)}currentScrollExtent(){return{pos:Math.abs(this.doc().scrollLeft),size:this.wnd.innerWidth}}reportProgress(e){if(!this.comms.ready)return;let t=this.doc().scrollWidth,n=this.wnd.innerWidth,r=Math.max(1,t-n),i=Math.abs(this.doc().scrollLeft),a=Math.max(0,Math.min(1,i/r)),o=Math.max(0,Math.min(1,(i+n)/t));this.comms.send(`progress`,{start:a,end:o,fragmentId:e===void 0?this.currentTimelineFragment():e,visibleFragmentIds:this.sortedVisibleFragmentIds()})}enableScrollProtection(){this.patternAnalyzer||(this.patternAnalyzer=new bs(_s),this.isScrollProtectionEnabled=!0,this.comms?.log(`Scroll protection enabled`))}mount(t,n){this.wnd=t,this.comms=n,this.initialScrollHandled=!1,this.lastScrollLeft=0,this.isResizing=!1,this.verticalLR=ka(t),this.resizeDebounce&&=(this.wnd.clearTimeout(this.resizeDebounce),null),t.navigator.epubReadingSystem&&(t.navigator.epubReadingSystem.layoutStyle=`scrolling`);let r=t.document.createElement(`style`);return r.dataset.readium=`true`,r.id=yc,r.textContent=`
        * {
            scrollbar-width: none;
        }
        body::-webkit-scrollbar {
            display: none;
        }
        html {
            overflow-x: auto !important;
            overflow-y: hidden !important;
        }
        `,t.document.head.appendChild(r),this.resizeObserver=new ResizeObserver(()=>{this.resizeDebounce&&this.wnd.clearTimeout(this.resizeDebounce),this.isResizing=!0,this.resizeDebounce=this.wnd.setTimeout(()=>{this.isResizing=!1,this.resizeDebounce=null,this.refreshFragmentStarts(),this.reportProgress()},50)}),this.resizeObserver.observe(t.document.body),t.addEventListener(`scroll`,this.handleScroll,{passive:!0}),n.register(`force_webkit_recalc`,e.moduleName,()=>{Fa(this.wnd);let e=this.doc().scrollLeft;this.verticalLR?this.doc().scrollLeft=e>1?e-1:e+1:this.doc().scrollLeft=e<-1?e+1:e-1,this.doc().scrollLeft=e}),n.register(`go_progression`,e.moduleName,(e,t)=>{let r=e;r<0||r>1?(n.send(`error`,{message:`go_progression must be given a position from 0.0 to 1.0`}),t(!1)):this.wnd.requestAnimationFrame(()=>{let e=this.scrollable()*r;this.doc().scrollLeft=this.verticalLR?e:-e,this.reportProgress(this.fragmentFromGeometry()),H(this.wnd),t(!0)})}),n.register(`go_id`,e.moduleName,(e,n)=>{let r=t.document.getElementById(e);r?this.wnd.requestAnimationFrame(()=>{this.doc().scrollLeft+=r.getBoundingClientRect().left-t.innerWidth/2;let i=e;this.reportProgress(this.timelineEntries.has(i)?i:this.nearestPrecedingTimelineEntry(r)),H(this.wnd),n(!0)}):n(!1)}),n.register(`go_text`,e.moduleName,(e,n)=>{let r;Array.isArray(e)&&(e.length>1&&(r=e[1]),e=e[0]);let i=A.deserialize(e),a=as(this.wnd.document,new j({href:t.location.href,type:`text/html`,text:i,locations:r?new k({otherLocations:new Map([[`cssSelector`,r]])}):void 0}));a?this.wnd.requestAnimationFrame(()=>{this.doc().scrollLeft+=a.getBoundingClientRect().left-t.innerWidth/2,this.reportProgress(this.nearestPrecedingTimelineEntry(a.startContainer)),H(this.wnd),n(!0)}):n(!1)}),n.register(`go_start`,e.moduleName,(e,t)=>{if(this.doc().scrollLeft===0)return t(!1);this.doc().scrollLeft=0,this.reportProgress(this.firstFragmentIfReached()),t(!0)}),n.register(`go_end`,e.moduleName,(e,t)=>{if(Math.abs(this.doc().scrollLeft)===this.scrollable())return t(!1);this.doc().scrollLeft=this.verticalLR?this.scrollable():-this.scrollable(),this.reportProgress(this.sortedFragmentIds[this.sortedFragmentIds.length-1]),t(!0)}),n.register([`go_next`,`go_prev`],e.moduleName,(e,t)=>t(!1)),n.register(`unfocus`,e.moduleName,(e,t)=>{H(this.wnd),t(!0)}),n.register(`scroll_protection`,e.moduleName,(e,t)=>{this.enableScrollProtection(),t(!0)}),n.register(`focus`,e.moduleName,(e,t)=>{this.reportProgress(),t(!0)}),n.register(`first_visible_locator`,e.moduleName,(e,n)=>{let r=ds(t,!0);this.comms.send(`first_visible_locator`,r.serialize()),n(!0)}),n.register(`timeline_entries`,e.moduleName,(e,n)=>{this.updateTimelineEntries(Array.isArray(e)?e:[],t),n(!0)}),n.log(`CJKVerticalSnapper Mounted`),!0}unmount(t,n){return n.unregisterAll(e.moduleName),this.resizeObserver.disconnect(),this.handleScroll&&t.removeEventListener(`scroll`,this.handleScroll),t.document.getElementById(yc)?.remove(),this.patternAnalyzer&&(this.patternAnalyzer.clear(),this.patternAnalyzer=null,this.isScrollProtectionEnabled=!1),this.timelineEntries.clear(),this.cachedFragmentIds=[],this.sortedFragmentIds=[],this.cachedFragmentStarts.clear(),n.log(`CJKVerticalSnapper Unmounted`),!0}};bc.moduleName=`cjk_vertical_snapper`;var xc=bc,Sc=[`fixed_setup`,`decorator`,`peripherals`,`print_protection`],Cc=[`reflowable_setup`,`decorator`,`peripherals`,`column_snapper`,`scroll_snapper`,`cjk_vertical_snapper`,`print_protection`],wc=[`webpub_setup`,`webpub_snapper`,`decorator`,`peripherals`,`print_protection`],Tc=new Map([Hs,zs,gc,ks,Ps,mc,ws,Ds,xc,vc].map(e=>[e.moduleName,e])),Ec=class{constructor(e=window,t=[]){this.loadedModules=[],this.wnd=e,this.comms=new wa(e);let n=[...new Set(t)];if(n.length){if(typeof e>`u`)throw Error(`Loader is not in a web browser`);e.parent!==e&&this.comms.log(`Loader is probably in a frame`),this.loadedModules=n.map(e=>{let t=this.loadModule(e);if(t)return t.mount(this.wnd,this.comms),t}).filter(e=>e!==void 0)}}loadModule(e){let t=Tc.get(e);return t===void 0?(this.comms.log(`Module "${name}" does not exist in the library`),t):new t}addModule(e){let t=this.loadModule(e);return!t||!t.mount(this.wnd,this.comms)?!1:(this.loadedModules.push(t),!0)}removeModule(e){let t=Tc.get(e);if(t===void 0)return this.comms.log(`Module "${e}" does not exist in the library`),!1;let n=this.loadedModules.findIndex(e=>e instanceof t);return n<0?!1:(this.loadedModules[n].unmount(this.wnd,this.comms),this.loadedModules.splice(n,1),!0)}destroy(){this.comms.destroy(),this.loadedModules.forEach(e=>e.unmount(this.wnd,this.comms)),this.loadedModules=[]}},Dc={type:`developer_tools`,keyCombos:[{keyCode:73,meta:!0,alt:!0},{keyCode:73,ctrl:!0,shift:!0},{keyCode:74,meta:!0,alt:!0},{keyCode:74,ctrl:!0,shift:!0},{keyCode:85,meta:!0,alt:!0},{keyCode:67,meta:!0,alt:!0},{keyCode:67,meta:!0,shift:!0},{keyCode:67,ctrl:!0,shift:!0},{keyCode:65,meta:!0,alt:!0},{keyCode:84,meta:!0,shift:!0,alt:!0},{keyCode:67,shift:!0,alt:!0},{keyCode:123},{keyCode:123,shift:!0},{keyCode:123,ctrl:!0,shift:!0},{keyCode:123,meta:!0,alt:!0}]},Oc={type:`select_all`,keyCombos:[{keyCode:65,meta:!0},{keyCode:65,ctrl:!0}]},kc={type:`print`,keyCombos:[{keyCode:80,meta:!0},{keyCode:80,ctrl:!0},{keyCode:80,meta:!0,shift:!0},{keyCode:80,ctrl:!0,shift:!0},{keyCode:80,meta:!0,alt:!0},{keyCode:80,ctrl:!0,alt:!0}]},Ac={type:`save`,keyCombos:[{keyCode:83,meta:!0},{keyCode:83,ctrl:!0}]},jc=class{mergeKeyboardPeripherals(e,t=[]){let n=[],r=t.filter(e=>![`developer_tools`,`select_all`,`print`,`save`].includes(e.type));e.disableSelectAll&&n.push(Oc),e.disableSave&&n.push(Ac),e.monitorDevTools&&n.push(Dc),e.protectPrinting?.disable&&n.push(kc);for(let e of r){let t=e.keyCombos.filter(e=>!n.some(t=>t.keyCombos.some(t=>e.keyCode===t.keyCode&&e.ctrl===t.ctrl&&e.shift===t.shift&&e.alt===t.alt&&e.meta===t.meta)));t.length>0&&n.push({...e,keyCombos:t})}return n}},Mc=class extends jc{goLeft(e=!1,t){this.readingProgression===R.ltr?this.goBackward(e,t):this.readingProgression===R.rtl&&this.goForward(e,t)}goRight(e=!1,t){this.readingProgression===R.ltr?this.goForward(e,t):this.readingProgression===R.rtl&&this.goBackward(e,t)}},Nc=class extends jc{},Pc=new Set(Object.values(W));function Fc(e,t){return e===W.TextColor?typeof window<`u`&&`Highlight`in window:Pc.has(e)?!0:!!t?.[e]}function Ic(e,t){let{style:n}=e;if(n.type===W.Template){let t=n;return{...e,style:{...t,element:Lc(t,e)}}}if(n.type&&t?.[n.type]){let r=t[n.type];return{...e,style:{type:W.Template,layout:r.layout,width:r.width,stylesheet:r.stylesheet,element:Lc(r,e)}}}return e}function Lc(e,t){return typeof e.element==`function`?e.element(t):e.element}function Rc(e,t){if(e.type!==t.type)return!1;if(e.type===W.Template){let n=e,r=t;return n.layout===r.layout&&n.width===r.width&&n.stylesheet===r.stylesheet}let n=e,r=t;return n.tint===r.tint&&n.layout===r.layout&&n.width===r.width&&(n.enforceContrast??!0)===(r.enforceContrast??!0)&&(n.expand??0)===(r.expand??0)}function zc(e,t){return e.locator.href===t.locator.href&&JSON.stringify(e.locator.locations?.serialize?.()??e.locator.locations)===JSON.stringify(t.locator.locations?.serialize?.()??t.locator.locations)&&JSON.stringify(e.locator.text??null)===JSON.stringify(t.locator.text??null)&&Rc(e.style,t.style)&&JSON.stringify(e.extras??null)===JSON.stringify(t.extras??null)}var Bc=class{constructor(e,t,n,r){this.injector=null,this.pub=e,this.item=n,this.burl=n.toURL(t)||``,this.cssProperties=r.cssProperties,this.injector=r.injector??null}async build(){if(!this.item.mediaType.isHTML)throw Error(`Unsupported media type for WebPub: ${this.item.mediaType.string}`);return await this.buildHtmlFrame()}async buildHtmlFrame(){let e=await this.pub.get(this.item).readAsString();if(!e)throw Error(`Failed reading item ${this.item.href}`);let t=new DOMParser().parseFromString(e,this.item.mediaType.string),n=t.querySelector(`parsererror`);if(n){let e=n.querySelector(`div`);throw Error(`Failed parsing item ${this.item.href}: ${e?.textContent||n.textContent}`)}return this.injector&&await this.injector.injectForDocument(t,this.item),this.finalizeDOM(t,this.burl,this.item.mediaType,e,this.cssProperties)}setProperties(e,t){for(let n in e){let r=e[n];r&&t.documentElement.style.setProperty(n,r)}}finalizeDOM(e,t,n,r,i){if(!e)return``;if(i&&this.setProperties(i,e),e.body.querySelectorAll(`img`).forEach(e=>{e.setAttribute(`fetchpriority`,`high`)}),t!==void 0){let n=e.createElement(`base`);n.href=t,n.dataset.readium=`true`,e.head.firstChild.before(n)}let a;return a=n.string===`application/xhtml+xml`?new XMLSerializer().serializeToString(e):this.serializeAsHTML(e,r||``),URL.createObjectURL(new Blob([a],{type:n.isHTML?n.string:`application/xhtml+xml`}))}serializeAsHTML(e,t){let n=t.match(/<!DOCTYPE[^>]*>/i);return(n?n[0]+`
`:``)+e.documentElement.outerHTML}},Vc=1e4,Hc=5e3,Uc=class{constructor(e,t){this.registry=new Map,this._ready=!1,this.listenerBuffer=[],this.visibleTime=0,this.visibleSince=document.hidden?void 0:performance.now(),this.visibilityHandler=this.handleVisibility.bind(this),this.handler=this.handle.bind(this),this.wnd=e,this.origin=t;try{this.channelId=window.crypto.randomUUID()}catch{this.channelId=Ca()}this.startGc(),window.addEventListener(`message`,this.handler),this.send(`_ping`,void 0)}set listener(e){this.listenerBuffer.length>0&&this.listenerBuffer.forEach(t=>e(t[0],t[1])),this.listenerBuffer=[],this._listener=e}clearListener(){typeof this._listener==`function`&&(this._listener=void 0)}startGc(){this.gc===void 0&&(this.handleVisibility(),document.addEventListener(`visibilitychange`,this.visibilityHandler),this.gc=setInterval(()=>{let e=this.visibleNow();this.registry.forEach((t,n)=>{e-t.time>Vc&&(console.warn(n,`event for`,t.key,`was never handled!`),this.registry.delete(n))})},Hc))}stopGc(){this.visibleTime=this.visibleNow(),this.visibleSince=void 0,document.removeEventListener(`visibilitychange`,this.visibilityHandler),clearInterval(this.gc),this.gc=void 0}visibleNow(){return this.visibleTime+(this.visibleSince===void 0?0:performance.now()-this.visibleSince)}handleVisibility(){document.hidden?(this.visibleTime=this.visibleNow(),this.visibleSince=void 0):this.visibleSince===void 0&&(this.visibleSince=performance.now())}halt(){this._ready=!1,window.removeEventListener(`message`,this.handler),this.stopGc(),this._listener=void 0,this.registry.clear()}resume(){window.addEventListener(`message`,this.handler),this.startGc(),this._ready=!0}handle(e){let t=e.data;if(!t._readium)console.warn(`Ignoring`,t);else if(t._channel===this.channelId)switch(t.key){case`_ack`:{if(!t.id)return;let e=this.registry.get(t.id);if(!e)return;this.registry.delete(t.id),e.cb(!!t.data);return}case`_pong`:this._ready=!0;default:if(!this.ready)return;typeof this._listener==`function`?this._listener(t.key,t.data):this.listenerBuffer.push([t.key,t.data])}}get ready(){return this._ready}send(e,t,n,r=!1,i=[]){let a=Ca();return n&&this.registry.set(a,{cb:n,time:this.visibleNow(),key:e}),this.wnd.postMessage({_readium:1,_channel:this.channelId,id:a,data:t,key:e,strict:r},`/`,i),a}},Wc=class{constructor(e,t){this.config=e,this.onUpdate=t,this.unsubs=[],this.conditionValues=new Map}setup(){let e=!0,t=new Map;this.config.forEach(e=>e.keyCombos.forEach(e=>{if(e.condition){let n=t.get(e.condition)??[];n.push(e),t.set(e.condition,n)}})),t.forEach((t,n)=>{let r=n.subscribe(n=>{t.forEach(e=>this.conditionValues.set(e,n)),e||this.onUpdate(this.buildSerializable())});this.unsubs.push(r)}),e=!1,this.onUpdate(this.buildSerializable())}buildSerializable(){return this.config.map(e=>({...e,keyCombos:e.keyCombos.filter(e=>!e.condition||this.conditionValues.get(e)===!0).map(({condition:e,...t})=>t)})).filter(e=>e.keyCombos.length>0)}destroy(){this.unsubs.forEach(e=>e()),this.unsubs=[],this.conditionValues.clear()}};function Gc(){let e=Promise.resolve();return t=>{let n=e.then(t);return e=n.catch(()=>{}),n}}var Kc=class{constructor(e,t={},n=[],r=[],i=[]){this.timelineFragmentIds=r,this.hidden=!0,this.destroyed=!1,this.pendingUnwatchSelectors=[],this.currModules=[],this.serialize=Gc(),this.frame=document.createElement(`iframe`),this.frame.classList.add(`readium-navigator-iframe`),this.frame.style.visibility=`hidden`,this.frame.ariaHidden=`true`,this.frame.style.opacity=`0`,this.frame.style.position=`absolute`,this.frame.style.pointerEvents=`none`,this.frame.style.transition=`visibility 0s, opacity 0.1s linear`,this.frame.style.backgroundColor=`#FFFFFF`,this.source=e,this.contentProtectionConfig={...t},this.keyboardPeripheralsConfig=[...n],this.resizeWatchSelectors=[...i]}async load(e=[]){return this.serialize(()=>new Promise((t,n)=>{if(this.loader){let n=this.frame.contentWindow;if([...this.currModules].sort().join(`|`)===[...e].sort().join(`|`)){try{t(n)}catch{}return}this.comms?.halt(),this.loader.destroy(),this.loader=new Ec(n,e),this.currModules=e,this.comms=void 0;try{t(n)}catch{}}else this.frame.onload=()=>{let n=this.frame.contentWindow;this.loader=new Ec(n,e),this.currModules=e;try{t(n)}catch{}},this.frame.onerror=e=>{try{n(e)}catch{}},this.frame.contentWindow.location.replace(this.source)}))}applyContentProtection(){this.comms||this.comms.resume(),this.comms.send(`peripherals_protection`,this.contentProtectionConfig),this.keyboardPeripheralsConfig&&this.keyboardPeripheralsConfig.length>0&&(this.conditionBridge?.destroy(),this.conditionBridge=new Wc(this.keyboardPeripheralsConfig,e=>{e.length>0&&this.comms.send(`keyboard_peripherals`,e)}),this.conditionBridge.setup()),this.contentProtectionConfig.monitorScrollingExperimental&&this.comms.send(`scroll_protection`,{}),this.contentProtectionConfig.protectPrinting?.disable&&this.comms.send(`print_protection`,this.contentProtectionConfig.protectPrinting),this.resizeWatchSelectors.forEach(e=>{this.comms.send(`decoration_resize`,{action:`watch`,selector:e})}),this.pendingUnwatchSelectors.forEach(e=>{this.comms.send(`decoration_resize`,{action:`unwatch`,selector:e})}),this.pendingUnwatchSelectors=[]}addResizeTarget(e){this.resizeWatchSelectors.includes(e)||this.resizeWatchSelectors.push(e),this.pendingUnwatchSelectors=this.pendingUnwatchSelectors.filter(t=>t!==e),this.comms?.ready&&this.comms.send(`decoration_resize`,{action:`watch`,selector:e})}removeResizeTarget(e){this.resizeWatchSelectors=this.resizeWatchSelectors.filter(t=>t!==e),this.comms?.ready?this.comms.send(`decoration_resize`,{action:`unwatch`,selector:e}):this.pendingUnwatchSelectors.includes(e)||this.pendingUnwatchSelectors.push(e)}async destroy(){return this.serialize(async()=>{this.conditionBridge?.destroy(),await this.hideNow(),this.loader?.destroy(),this.frame.remove(),this.destroyed=!0})}async hide(){return this.serialize(()=>this.hideNow())}async hideNow(){if(!this.destroyed){if(this.frame.style.visibility=`hidden`,this.frame.ariaHidden=`true`,this.frame.style.opacity=`0`,this.frame.style.pointerEvents=`none`,this.hidden=!0,this.frame.parentElement)return this.comms===void 0||!this.comms.ready?void 0:new Promise((e,t)=>{this.comms?.send(`unfocus`,void 0,t=>{this.comms?.halt(),e()})});this.comms?.halt()}}async show(e){return this.serialize(()=>this.showNow(e))}async showNow(e){if(this.destroyed)throw Error(`Trying to show frame when it doesn't exist`);if(!this.frame.parentElement)throw Error(`Trying to show frame that is not attached to the DOM`);return this.comms?this.comms.resume():this.comms=new Uc(this.frame.contentWindow,this.source),new Promise((t,n)=>{this.comms?.send(`activate`,void 0,()=>{this.comms?.send(`focus`,void 0,()=>{this.applyContentProtection(),this.timelineFragmentIds.length>0&&this.comms?.send(`timeline_entries`,this.timelineFragmentIds);let n=()=>{this.frame.style.removeProperty(`visibility`),this.frame.ariaHidden=null,this.frame.style.removeProperty(`opacity`),this.frame.style.removeProperty(`pointer-events`),this.hidden=!1,B.UA.WebKit&&this.comms?.send(`force_webkit_recalc`,void 0),t()};e===void 0?n():this.comms?.send(`go_progression`,e,n)})})})}setCSSProperties(e){this.destroyed||!this.frame.contentWindow||(this.hidden&&!this.comms&&(this.comms=new Uc(this.frame.contentWindow,this.source),this.comms.halt()),this.comms?.send(`update_properties`,e))}get iframe(){if(this.destroyed)throw Error(`Trying to use frame when it doesn't exist`);return this.frame}get realSize(){if(this.destroyed)throw Error(`Trying to use frame client rect when it doesn't exist`);return this.frame.getBoundingClientRect()}get window(){if(this.destroyed||!this.frame.contentWindow)throw Error(`Trying to use frame window when it doesn't exist`);return this.frame.contentWindow}get msg(){return this.comms}get ldr(){return this.loader}},qc=class{constructor(e,t,n,r={},i=[],a,o=[]){this.pool=new Map,this.blobs=new Map,this.inprogress=new Map,this.pendingUpdates=new Map,this.injector=null,this.container=e,this.currentCssProperties=t,this.injector=n,this.contentProtectionConfig=r,this.keyboardPeripheralsConfig=[...i],this.getFragmentIds=a??(()=>[]),this.resizeWatchSelectors=[...o]}addResizeTarget(e){this.resizeWatchSelectors.includes(e)||this.resizeWatchSelectors.push(e),this.pool.forEach(t=>t.addResizeTarget(e))}removeResizeTarget(e){this.resizeWatchSelectors=this.resizeWatchSelectors.filter(t=>t!==e),this.pool.forEach(t=>t.removeResizeTarget(e))}async destroy(){let e=this.inprogress.values(),t=e.next(),n=[];for(;t.value;)n.push(t.value),t=e.next();n.length>0&&await Promise.allSettled(n),this.inprogress.clear();let r=this.pool.values(),i=r.next();for(;i.value;)await i.value.destroy(),i=r.next();this.pool.clear(),this.blobs.forEach(e=>{this.injector?.releaseBlobUrl?.(e),URL.revokeObjectURL(e)}),this.blobs.clear(),this.injector?.dispose(),this.container.childNodes.forEach(e=>{(e.nodeType===Node.ELEMENT_NODE||e.nodeType===Node.TEXT_NODE)&&e.remove()})}async update(e,t,n){let r=e.readingOrder.items,i=r.findIndex(e=>e.href===t.href);if(i<0)throw Error(`Locator not found in reading order: ${t.href}`);let a=r[i].href;this.inprogress.has(a)&&await this.inprogress.get(a);let o=new Promise(async(r,o)=>{let s=[],c=[];e.readingOrder.items.forEach((e,t)=>{t!==i&&t!==i-1&&t!==i+1&&(s.includes(e.href)||s.push(e.href)),t===i&&(c.includes(e.href)||c.push(e.href))}),s.forEach(async e=>{c.includes(e)||this.pool.has(e)&&(await this.pool.get(e)?.destroy(),this.pool.delete(e))}),this.currentBaseURL!==void 0&&e.baseURL!==this.currentBaseURL&&(this.blobs.forEach(e=>{this.injector?.releaseBlobUrl?.(e),URL.revokeObjectURL(e)}),this.blobs.clear()),this.currentBaseURL=e.baseURL;let l=async t=>{if(this.pendingUpdates.has(t)&&this.pendingUpdates.get(t)?.inPool===!1){let e=this.blobs.get(t);e&&(this.injector?.releaseBlobUrl?.(e),URL.revokeObjectURL(e),this.blobs.delete(t),this.pendingUpdates.delete(t))}if(this.pool.has(t)){let e=this.pool.get(t);if(!this.blobs.has(t))await e.destroy(),this.pool.delete(t),this.pendingUpdates.delete(t);else{await e.load(n);return}}let r=e.readingOrder.findWithHref(t);if(!r)return;if(!this.blobs.has(t)){let n=await new Bc(e,this.currentBaseURL||``,r,{cssProperties:this.currentCssProperties,injector:this.injector}).build();this.blobs.set(t,n)}let i=new Kc(this.blobs.get(t),this.contentProtectionConfig,this.keyboardPeripheralsConfig,this.getFragmentIds(t),this.resizeWatchSelectors);t!==a&&await i.hide(),this.container.appendChild(i.iframe),await i.load(n),this.pool.set(t,i)};try{await Promise.all(c.map(e=>l(e)))}catch(e){o(e)}let u=this.pool.get(a);if(u?.source!==this._currentFrame?.source&&(await this._currentFrame?.hide(),u&&await u.load(n),u&&await u.show(t.locations.progression),this._currentFrame=u,u)){let e=this.container.ownerDocument.activeElement;e&&e.tagName===`IFRAME`&&e!==u.iframe&&u.iframe.focus({preventScroll:!0})}r()});this.inprogress.set(a,o);try{await o}finally{this.inprogress.delete(a)}}setCSSProperties(e){if(!((e,t)=>{let n=Object.keys(e),r=Object.keys(t);if(n.length!==r.length)return!1;for(let r of n)if(e[r]!==t[r])return!1;return!0})(this.currentCssProperties||{},e)){this.currentCssProperties=e,this.pool.forEach(t=>{t.setCSSProperties(e)});for(let e of this.blobs.keys())this.pendingUpdates.set(e,{inPool:this.pool.has(e)})}}get currentFrames(){return[this._currentFrame]}get currentBounds(){let e={x:0,y:0,width:0,height:0,top:0,right:0,bottom:0,left:0,toJSON(){return this}};return this.currentFrames.forEach(t=>{if(!t)return;let n=t.realSize;e.x=Math.min(e.x,n.x),e.y=Math.min(e.y,n.y),e.width+=n.width,e.height=Math.max(e.height,n.height),e.top=Math.min(e.top,n.top),e.right=Math.min(e.right,n.right),e.bottom=Math.min(e.bottom,n.bottom),e.left=Math.min(e.left,n.left)}),e}},Jc,Yc;function Xc(){if(Yc)return Jc;Yc=1;function e(e){if(typeof e!=`string`)throw TypeError(`Path must be a string. Received `+JSON.stringify(e))}function t(e,t){for(var n=``,r=0,i=-1,a=0,o,s=0;s<=e.length;++s){if(s<e.length)o=e.charCodeAt(s);else{if(o===47)break;o=47}if(o===47){if(i!==s-1&&a!==1){if(i!==s-1&&a===2){if(n.length<2||r!==2||n.charCodeAt(n.length-1)!==46||n.charCodeAt(n.length-2)!==46){if(n.length>2){var c=n.lastIndexOf(`/`);if(c!==n.length-1){c===-1?(n=``,r=0):(n=n.slice(0,c),r=n.length-1-n.lastIndexOf(`/`)),i=s,a=0;continue}}else if(n.length===2||n.length===1){n=``,r=0,i=s,a=0;continue}}t&&(n.length>0?n+=`/..`:n=`..`,r=2)}else n.length>0?n+=`/`+e.slice(i+1,s):n=e.slice(i+1,s),r=s-i-1}i=s,a=0}else o===46&&a!==-1?++a:a=-1}return n}function n(e,t){var n=t.dir||t.root,r=t.base||(t.name||``)+(t.ext||``);return n?n===t.root?n+r:n+e+r:r}var r={resolve:function(){for(var n=``,r=!1,i,a=arguments.length-1;a>=-1&&!r;a--){var o;a>=0?o=arguments[a]:(i===void 0&&(i=process.cwd()),o=i),e(o),o.length!==0&&(n=o+`/`+n,r=o.charCodeAt(0)===47)}return n=t(n,!r),r?n.length>0?`/`+n:`/`:n.length>0?n:`.`},normalize:function(n){if(e(n),n.length===0)return`.`;var r=n.charCodeAt(0)===47,i=n.charCodeAt(n.length-1)===47;return n=t(n,!r),n.length===0&&!r&&(n=`.`),n.length>0&&i&&(n+=`/`),r?`/`+n:n},isAbsolute:function(t){return e(t),t.length>0&&t.charCodeAt(0)===47},join:function(){if(arguments.length===0)return`.`;for(var t,n=0;n<arguments.length;++n){var i=arguments[n];e(i),i.length>0&&(t===void 0?t=i:t+=`/`+i)}return t===void 0?`.`:r.normalize(t)},relative:function(t,n){if(e(t),e(n),t===n||(t=r.resolve(t),n=r.resolve(n),t===n))return``;for(var i=1;i<t.length&&t.charCodeAt(i)===47;++i);for(var a=t.length,o=a-i,s=1;s<n.length&&n.charCodeAt(s)===47;++s);for(var c=n.length-s,l=o<c?o:c,u=-1,d=0;d<=l;++d){if(d===l){if(c>l){if(n.charCodeAt(s+d)===47)return n.slice(s+d+1);if(d===0)return n.slice(s+d)}else o>l&&(t.charCodeAt(i+d)===47?u=d:d===0&&(u=0));break}var f=t.charCodeAt(i+d);if(f!==n.charCodeAt(s+d))break;f===47&&(u=d)}var p=``;for(d=i+u+1;d<=a;++d)(d===a||t.charCodeAt(d)===47)&&(p.length===0?p+=`..`:p+=`/..`);return p.length>0?p+n.slice(s+u):(s+=u,n.charCodeAt(s)===47&&++s,n.slice(s))},_makeLong:function(e){return e},dirname:function(t){if(e(t),t.length===0)return`.`;for(var n=t.charCodeAt(0),r=n===47,i=-1,a=!0,o=t.length-1;o>=1;--o)if(n=t.charCodeAt(o),n===47){if(!a){i=o;break}}else a=!1;return i===-1?r?`/`:`.`:r&&i===1?`//`:t.slice(0,i)},basename:function(t,n){if(n!==void 0&&typeof n!=`string`)throw TypeError(`"ext" argument must be a string`);e(t);var r=0,i=-1,a=!0,o;if(n!==void 0&&n.length>0&&n.length<=t.length){if(n.length===t.length&&n===t)return``;var s=n.length-1,c=-1;for(o=t.length-1;o>=0;--o){var l=t.charCodeAt(o);if(l===47){if(!a){r=o+1;break}}else c===-1&&(a=!1,c=o+1),s>=0&&(l===n.charCodeAt(s)?--s===-1&&(i=o):(s=-1,i=c))}return r===i?i=c:i===-1&&(i=t.length),t.slice(r,i)}for(o=t.length-1;o>=0;--o)if(t.charCodeAt(o)===47){if(!a){r=o+1;break}}else i===-1&&(a=!1,i=o+1);return i===-1?``:t.slice(r,i)},extname:function(t){e(t);for(var n=-1,r=0,i=-1,a=!0,o=0,s=t.length-1;s>=0;--s){var c=t.charCodeAt(s);if(c===47){if(!a){r=s+1;break}}else i===-1&&(a=!1,i=s+1),c===46?n===-1?n=s:o!==1&&(o=1):n!==-1&&(o=-1)}return n===-1||i===-1||o===0||o===1&&n===i-1&&n===r+1?``:t.slice(n,i)},format:function(e){if(typeof e!=`object`||!e)throw TypeError(`The "pathObject" argument must be of type Object. Received type `+typeof e);return n(`/`,e)},parse:function(t){e(t);var n={root:``,dir:``,base:``,ext:``,name:``};if(t.length===0)return n;var r=t.charCodeAt(0),i=r===47,a;i?(n.root=`/`,a=1):a=0;for(var o=-1,s=0,c=-1,l=!0,u=t.length-1,d=0;u>=a;--u)if(r=t.charCodeAt(u),r===47){if(!l){s=u+1;break}}else c===-1&&(l=!1,c=u+1),r===46?o===-1?o=u:d!==1&&(d=1):o!==-1&&(d=-1);return o===-1||c===-1||d===0||d===1&&o===c-1&&o===s+1?c!==-1&&(n.base=n.name=s===0&&i?t.slice(1,c):t.slice(s,c)):(s===0&&i?(n.name=t.slice(1,o),n.base=t.slice(1,c)):(n.name=t.slice(s,o),n.base=t.slice(s,c)),n.ext=t.slice(o,c)),s>0?n.dir=t.slice(0,s-1):i&&(n.dir=`/`),n},sep:`/`,delimiter:`:`,win32:null,posix:null};return r.posix=r,Jc=r,Jc}var Zc=Xc();function Qc(e){let t=e.languages?.[0]?.toLowerCase(),n=e.readingProgression;if(t){if(t.startsWith(`zh`)||t.startsWith(`ja`)||t.startsWith(`ko`))return n===R.rtl?`cjk-vertical`:`cjk-horizontal`;if(t.startsWith(`mn-mong`))return`mongolian-vertical`;if(t.startsWith(`ar`)||t.startsWith(`fa`)||t.startsWith(`he`))return`rtl`}return`ltr`}var $c={experimentalHeaderFiltering:{description:`Attempts to filter out paragraphs that are implicitly headings or part of headers`,scope:`RS`,value:`readium-experimentalHeaderFiltering-on`},experimentalZoom:{description:`Attempts to filter out elements that are sized using viewport units and should not be scaled directly e.g. tables, images, iframes, etc.`,scope:`RS`,value:`readium-experimentalZoom-on`}},el={ltr:{disabled:[],added:[]},rtl:{disabled:[`bodyHyphens`,`a11yNormalize`,`letterSpacing`],added:[]},"cjk-horizontal":{disabled:[`textAlign`,`bodyHyphens`,`a11yNormalize`,`ligatures`,`paraIndent`,`wordSpacing`],added:[`noRuby`]},"cjk-vertical":{disabled:[`colCount`,`textAlign`,`bodyHyphens`,`a11yNormalize`,`ligatures`,`paraIndent`,`wordSpacing`],added:[`noRuby`]}},tl={latin:{baseFontFamily:`var(--RS__oldStyleTf)`,lineHeightCompensation:1},am:{baseFontFamily:`Kefa, Nyala, Roboto, Noto, 'Noto Sans Ethiopic', serif`,lineHeightCompensation:1.167},ar:{baseFontFamily:`'Geeza Pro', 'Arabic Typesetting', Roboto, Noto, 'Noto Naskh Arabic', 'Times New Roman', serif`},bn:{baseFontFamily:`'Kohinoor Bangla', 'Bangla Sangam MN', Vrinda, Roboto, Noto, 'Noto Sans Bengali', sans-serif`,lineHeightCompensation:1.067},bo:{baseFontFamily:`Kailasa, 'Microsoft Himalaya', Roboto, Noto, 'Noto Sans Tibetan', sans-serif`},chr:{baseFontFamily:`'Plantagenet Cherokee', Roboto, Noto, 'Noto Sans Cherokee'`,lineHeightCompensation:1.167},fa:{baseFontFamily:`'Geeza Pro', 'Arabic Typesetting', Roboto, Noto, 'Noto Naskh Arabic', 'Times New Roman', serif`},gu:{baseFontFamily:`'Gujarati Sangam MN', 'Nirmala UI', Shruti, Roboto, Noto, 'Noto Sans Gujarati', sans-serif`,lineHeightCompensation:1.167},he:{baseFontFamily:`'New Peninim MT', 'Arial Hebrew', Gisha, 'Times New Roman', Roboto, Noto, 'Noto Sans Hebrew', sans-serif`,lineHeightCompensation:1.1},hi:{baseFontFamily:`'Kohinoor Devanagari', 'Devanagari Sangam MN', Kokila, 'Nirmala UI', Roboto, Noto, 'Noto Sans Devanagari', sans-serif`,lineHeightCompensation:1.1},hy:{baseFontFamily:`Mshtakan, Sylfaen, Roboto, Noto, 'Noto Serif Armenian', serif`},iu:{baseFontFamily:`'Euphemia UCAS', Euphemia, Roboto, Noto, 'Noto Sans Canadian Aboriginal', sans-serif`},ja:{baseFontFamily:`YuGothic, 'Hiragino Maru Gothic ProN', 'Hiragino Sans', 'Yu Gothic UI', 'Meiryo UI', 'MS Gothic', Roboto, Noto, 'Noto Sans CJK JP', sans-serif`,lineHeightCompensation:1.167},km:{baseFontFamily:`'Khmer Sangam MN', 'Leelawadee UI', 'Khmer UI', Roboto, Noto, 'Noto Sans Khmer', sans-serif`,lineHeightCompensation:1.067},kn:{baseFontFamily:`'Kannada Sangam MN', 'Nirmala UI', Tunga, Roboto, Noto, 'Noto Sans Kannada', sans-serif`,lineHeightCompensation:1.1},ko:{baseFontFamily:`'Nanum Gothic', 'Apple SD Gothic Neo', 'Malgun Gothic', Roboto, Noto, 'Noto Sans CJK KR', sans-serif`,lineHeightCompensation:1.167},lo:{baseFontFamily:`'Lao Sangam MN', 'Leelawadee UI', 'Lao UI', Roboto, Noto, 'Noto Sans Lao', sans-serif`},ml:{baseFontFamily:`'Malayalam Sangam MN', 'Nirmala UI', Kartika, Roboto, Noto, 'Noto Sans Malayalam', sans-serif`,lineHeightCompensation:1.067},or:{baseFontFamily:`'Oriya Sangam MN', 'Nirmala UI', Kalinga, Roboto, Noto, 'Noto Sans Oriya', sans-serif`,lineHeightCompensation:1.167},pa:{baseFontFamily:`'Gurmukhi MN', 'Nirmala UI', Kartika, Roboto, Noto, 'Noto Sans Gurmukhi', sans-serif`,lineHeightCompensation:1.1},si:{baseFontFamily:`'Sinhala Sangam MN', 'Nirmala UI', 'Iskoola Pota', Roboto, Noto, 'Noto Sans Sinhala', sans-serif`,lineHeightCompensation:1.167},ta:{baseFontFamily:`'Tamil Sangam MN', 'Nirmala UI', Latha, Roboto, Noto, 'Noto Sans Tamil', sans-serif`,lineHeightCompensation:1.067},te:{baseFontFamily:`'Kohinoor Telugu', 'Telugu Sangam MN', 'Nirmala UI', Gautami, Roboto, Noto, 'Noto Sans Telugu', sans-serif`},th:{baseFontFamily:`Thonburi, 'Leelawadee UI', 'Cordia New', Roboto, Noto, 'Noto Sans Thai', sans-serif`,lineHeightCompensation:1.067},zh:{baseFontFamily:`'方体', 'PingFang SC', '黑体', 'Heiti SC', 'Microsoft JhengHei UI', 'Microsoft JhengHei', Roboto, Noto, 'Noto Sans CJK SC', sans-serif`,lineHeightCompensation:1.167},"zh-Hant":{baseFontFamily:`'方體', 'PingFang TC', '黑體', 'Heiti TC', 'Microsoft JhengHei UI', 'Microsoft JhengHei', Roboto, Noto, 'Noto Sans CJK TC', sans-serif`,lineHeightCompensation:1.167},"zh-TW":{baseFontFamily:`'方體', 'PingFang TC', '黑體', 'Heiti TC', 'Microsoft JhengHei UI', 'Microsoft JhengHei', Roboto, Noto, 'Noto Sans CJK TC', sans-serif`,lineHeightCompensation:1.167},"zh-HK":{baseFontFamily:`'方體', 'PingFang HK', '方體', 'PingFang TC', '黑體', 'Heiti TC', 'Microsoft JhengHei UI', 'Microsoft JhengHei', Roboto, Noto, 'Noto Sans CJK TC', sans-serif`,lineHeightCompensation:1.167}},nl=$c,rl=el,il=tl,al=(e=>(e.start=`start`,e.left=`left`,e.right=`right`,e.justify=`justify`,e))(al||{}),ol={range:[0,100],step:1},sl={range:[.7,4],step:.05},cl={range:[100,1e3],step:100},ll={range:[50,250],step:10},ul={range:[0,1],step:.125},dl={range:[1,2.5],step:.1},fl={range:[20,100],step:1},pl={range:[0,3],step:.25},ml={range:[0,3],step:.25},hl={range:[0,2],step:.125},gl={range:[.7,4],step:.05},_l={range:[0,1],step:.1},vl={range:[.5,4],step:.1},yl={range:[5,60],step:5},bl=class{constructor(){}toFlag(e){return`readium-${e}-on`}toUnitless(e){return e.toString()}toPercentage(e,t=!1){return t||e>0&&e<=1?`${Math.round(e*100)}%`:`${e}%`}toVw(e){let t=Math.round(e*100);return`${Math.min(t,100)}vw`}toVh(e){let t=Math.round(e*100);return`${Math.min(t,100)}vh`}toPx(e){return`${e}px`}toRem(e){return`${e}rem`}},xl=class extends bl{constructor(e){super(),this.a11yNormalize=e.a11yNormalize??null,this.bodyHyphens=e.bodyHyphens??null,this.fontFamily=e.fontFamily??null,this.fontWeight=e.fontWeight??null,this.iOSPatch=e.iOSPatch??null,this.iPadOSPatch=e.iPadOSPatch??null,this.letterSpacing=e.letterSpacing??null,this.ligatures=e.ligatures??null,this.lineHeight=e.lineHeight??null,this.noRuby=e.noRuby??null,this.paraIndent=e.paraIndent??null,this.paraSpacing=e.paraSpacing??null,this.textAlign=e.textAlign??null,this.wordSpacing=e.wordSpacing??null,this.zoom=e.zoom??null}toCSSProperties(){let e={};return this.a11yNormalize&&(e[`--USER__a11yNormalize`]=this.toFlag(`a11y`)),this.bodyHyphens&&(e[`--USER__bodyHyphens`]=this.bodyHyphens),this.fontFamily&&(e[`--USER__fontFamily`]=this.fontFamily),this.fontWeight!=null&&(e[`--USER__fontWeight`]=this.toUnitless(this.fontWeight)),this.iOSPatch&&(e[`--USER__iOSPatch`]=this.toFlag(`iOSPatch`)),this.iPadOSPatch&&(e[`--USER__iPadOSPatch`]=this.toFlag(`iPadOSPatch`)),this.letterSpacing!=null&&(e[`--USER__letterSpacing`]=this.toRem(this.letterSpacing)),this.ligatures&&(e[`--USER__ligatures`]=this.ligatures),this.lineHeight!=null&&(e[`--USER__lineHeight`]=this.toUnitless(this.lineHeight)),this.noRuby&&(e[`--USER__noRuby`]=this.toFlag(`noRuby`)),this.paraIndent!=null&&(e[`--USER__paraIndent`]=this.toRem(this.paraIndent)),this.paraSpacing!=null&&(e[`--USER__paraSpacing`]=this.toRem(this.paraSpacing)),this.textAlign&&(e[`--USER__textAlign`]=this.textAlign),this.wordSpacing!=null&&(e[`--USER__wordSpacing`]=this.toRem(this.wordSpacing)),this.zoom!==null&&(e[`--USER__zoom`]=this.toPercentage(this.zoom,!0)),e}},Sl=class extends bl{constructor(e){super(),this.experiments=e.experiments??null}toCSSProperties(){let e={};return this.experiments&&this.experiments.forEach(t=>{e[`--RS__`+t]=nl[t].value}),e}},Cl=class{constructor(e){this.rsProperties=e.rsProperties,this.userProperties=e.userProperties}update(e){e.experiments&&(this.rsProperties.experiments=e.experiments);let t={a11yNormalize:e.textNormalization,bodyHyphens:typeof e.hyphens==`boolean`?e.hyphens?`auto`:`none`:null,fontFamily:e.fontFamily,fontWeight:e.fontWeight,iOSPatch:e.iOSPatch,iPadOSPatch:e.iPadOSPatch,letterSpacing:e.letterSpacing,ligatures:typeof e.ligatures==`boolean`?e.ligatures?`common-ligatures`:`none`:null,lineHeight:e.lineHeight,noRuby:e.noRuby,paraIndent:e.paragraphIndent,paraSpacing:e.paragraphSpacing,textAlign:e.textAlign,wordSpacing:e.wordSpacing,zoom:e.zoom};this.userProperties=new xl(t)}};function wl(e,t){return e==null||t==null||e<=t?e:void 0}function Tl(e,t){return e==null||t==null||e>=t?e:void 0}function G(e){return typeof e==`string`?e:e===null?null:void 0}function K(e){return typeof e==`boolean`||e==null?e:void 0}function El(e,t){if(e!==void 0)return e===null?null:t[e]===void 0?void 0:e}function Dl(e){return typeof e==`boolean`||typeof e==`number`&&e>=0?e:e===null?null:void 0}function q(e){if(e!==void 0)return e===null?null:e<0?void 0:e}function J(e,t){if(e===void 0)return;if(e===null)return null;let n=Math.min(...t),r=Math.max(...t);return e>=n&&e<=r?e:void 0}function Ol(e,t){return e===void 0?t:e}function kl(e){if(e!==void 0)return e===null?null:e.filter(e=>e in nl)}var Al=class e{constructor(e={}){this.fontFamily=G(e.fontFamily),this.fontWeight=J(e.fontWeight,cl.range),this.hyphens=K(e.hyphens),this.iOSPatch=K(e.iOSPatch),this.iPadOSPatch=K(e.iPadOSPatch),this.letterSpacing=q(e.letterSpacing),this.ligatures=K(e.ligatures),this.lineHeight=q(e.lineHeight),this.noRuby=K(e.noRuby),this.paragraphIndent=q(e.paragraphIndent),this.paragraphSpacing=q(e.paragraphSpacing),this.textAlign=El(e.textAlign,al),this.textNormalization=K(e.textNormalization),this.wordSpacing=q(e.wordSpacing),this.zoom=J(e.zoom,gl.range)}static serialize(e){let{...t}=e;return JSON.stringify(t)}static deserialize(t){try{let n=JSON.parse(t);return new e(n)}catch(e){return console.error(`Failed to deserialize preferences:`,e),null}}merging(t){let n={...this};for(let e of Object.keys(t))t[e]!==void 0&&(n[e]=t[e]);return new e(n)}},jl=class{constructor(e){this.fontFamily=G(e.fontFamily)||null,this.fontWeight=J(e.fontWeight,cl.range)||null,this.hyphens=K(e.hyphens)??null,this.iOSPatch=e.iOSPatch!==!1&&(V.OS.iOS||V.OS.iPadOS)&&V.iOSRequest===`mobile`,this.iPadOSPatch=e.iPadOSPatch!==!1&&V.OS.iPadOS&&V.iOSRequest===`desktop`,this.letterSpacing=q(e.letterSpacing)||null,this.ligatures=K(e.ligatures)??null,this.lineHeight=q(e.lineHeight)||null,this.noRuby=K(e.noRuby)??!1,this.paragraphIndent=q(e.paragraphIndent)??null,this.paragraphSpacing=q(e.paragraphSpacing)??null,this.textAlign=El(e.textAlign,al)||null,this.textNormalization=K(e.textNormalization)??!1,this.wordSpacing=q(e.wordSpacing)||null,this.zoom=J(e.zoom,gl.range)||1,this.experiments=kl(e.experiments)??null}},Ml=class{constructor(e,t,n){this.fontFamily=null,this.fontWeight=null,this.hyphens=null,this.iOSPatch=null,this.iPadOSPatch=null,this.letterSpacing=null,this.ligatures=null,this.lineHeight=null,this.noRuby=null,this.paragraphIndent=null,this.paragraphSpacing=null,this.textAlign=null,this.textNormalization=null,this.wordSpacing=null,n&&(this.fontFamily=e.fontFamily||t.fontFamily||null,this.fontWeight=e.fontWeight===void 0?t.fontWeight===void 0?null:t.fontWeight:e.fontWeight,this.hyphens=typeof e.hyphens==`boolean`?e.hyphens:t.hyphens??null,this.iOSPatch=e.iOSPatch===!1?!1:e.iOSPatch===!0?(V.OS.iOS||V.OS.iPadOS)&&V.iOSRequest===`mobile`:t.iOSPatch,this.iPadOSPatch=e.iPadOSPatch===!1?!1:e.iPadOSPatch===!0?V.OS.iPadOS&&V.iOSRequest===`desktop`:t.iPadOSPatch,this.letterSpacing=e.letterSpacing===void 0?t.letterSpacing===void 0?null:t.letterSpacing:e.letterSpacing,this.ligatures=typeof e.ligatures==`boolean`?e.ligatures:t.ligatures??null,this.lineHeight=e.lineHeight===void 0?t.lineHeight===void 0?null:t.lineHeight:e.lineHeight,this.noRuby=typeof e.noRuby==`boolean`?e.noRuby:t.noRuby??null,this.paragraphIndent=e.paragraphIndent===void 0?t.paragraphIndent===void 0?null:t.paragraphIndent:e.paragraphIndent,this.paragraphSpacing=e.paragraphSpacing===void 0?t.paragraphSpacing===void 0?null:t.paragraphSpacing:e.paragraphSpacing,this.textAlign=e.textAlign||t.textAlign||null,this.textNormalization=typeof e.textNormalization==`boolean`?e.textNormalization:t.textNormalization??null,this.wordSpacing=e.wordSpacing===void 0?t.wordSpacing===void 0?null:t.wordSpacing:e.wordSpacing),this.zoom=e.zoom===void 0?t.zoom===void 0?null:t.zoom:e.zoom,this.experiments=t.experiments||null}},Y=class{constructor({initialValue:e=null,effectiveValue:t,isEffective:n,onChange:r}){this._value=e,this._effectiveValue=t,this._isEffective=n,this._onChange=r}set value(e){this._value=e,this._onChange(this._value)}get value(){return this._value}get effectiveValue(){return this._effectiveValue}get isEffective(){return this._isEffective}clear(){this._value=null}},X=class extends Y{set value(e){this._value=e,this._onChange(this._value)}get value(){return this._value}get effectiveValue(){return this._effectiveValue}get isEffective(){return this._isEffective}clear(){this._value=null}toggle(){this._value=!this._value,this._onChange(this._value)}},Nl=class extends Y{constructor({initialValue:e=null,effectiveValue:t,isEffective:n,onChange:r,supportedValues:i}){super({initialValue:e,effectiveValue:t,isEffective:n,onChange:r}),this._supportedValues=i}set value(e){if(e&&!this._supportedValues.includes(e))throw Error(`Value '${String(e)}' is not in the supported values for this preference.`);this._value=e,this._onChange(this._value)}get value(){return this._value}get effectiveValue(){return this._effectiveValue}get isEffective(){return this._isEffective}get supportedValues(){return this._supportedValues}clear(){this._value=null}},Z=class extends Y{constructor({initialValue:e=null,effectiveValue:t,isEffective:n,onChange:r,supportedRange:i,step:a}){super({initialValue:e,effectiveValue:t,isEffective:n,onChange:r}),this._supportedRange=i,this._step=a,this._decimals=this._step.toString().includes(`.`)?this._step.toString().split(`.`)[1].length:0}set value(e){if(e&&(e<this._supportedRange[0]||e>this._supportedRange[1]))throw Error(`Value '${String(e)}' is out of the supported range for this preference.`);this._value=e,this._onChange(this._value)}get value(){return this._value}get effectiveValue(){return this._effectiveValue}get isEffective(){return this._isEffective}get supportedRange(){return this._supportedRange}get step(){return this._step}increment(){this._value&&this._value<this._supportedRange[1]&&(this._value=Math.min(Math.round((this._value+this._step)*10**this._decimals)/10**this._decimals,this._supportedRange[1]),this._onChange(this._value))}decrement(){this._value&&this._value>this._supportedRange[0]&&(this._value=Math.max(Math.round((this._value-this._step)*10**this._decimals)/10**this._decimals,this._supportedRange[0]),this._onChange(this._value))}format(e){return e.toString()}clear(){this._value=null}},Pl=class{constructor(e,t,n){this.preferences=new Al({...e}),this.settings=t,this.metadata=n}clear(){this.preferences=new Al({fontFamily:null,fontWeight:null,hyphens:null,iOSPatch:null,iPadOSPatch:null,letterSpacing:null,ligatures:null,lineHeight:null,noRuby:null,paragraphIndent:null,paragraphSpacing:null,textAlign:null,textNormalization:null,wordSpacing:null,zoom:null})}updatePreference(e,t){this.preferences[e]=t}get isDisplayTransformable(){return this.metadata?.accessibility?.feature?.some(e=>e.value===x.DISPLAY_TRANSFORMABILITY.value)??!1}get fontFamily(){return new Y({initialValue:this.preferences.fontFamily,effectiveValue:this.settings.fontFamily||null,isEffective:this.isDisplayTransformable,onChange:e=>{this.updatePreference(`fontFamily`,e??null)}})}get fontWeight(){return new Z({initialValue:this.preferences.fontWeight,effectiveValue:this.settings.fontWeight||400,isEffective:this.isDisplayTransformable,onChange:e=>{this.updatePreference(`fontWeight`,e??null)},supportedRange:cl.range,step:cl.step})}get hyphens(){return new X({initialValue:this.preferences.hyphens,effectiveValue:this.settings.hyphens||!1,isEffective:this.isDisplayTransformable,onChange:e=>{this.updatePreference(`hyphens`,e??null)}})}get iOSPatch(){return new X({initialValue:this.preferences.iOSPatch,effectiveValue:this.settings.iOSPatch||!1,isEffective:!0,onChange:e=>{this.updatePreference(`iOSPatch`,e??null)}})}get iPadOSPatch(){return new X({initialValue:this.preferences.iPadOSPatch,effectiveValue:this.settings.iPadOSPatch||!1,isEffective:!0,onChange:e=>{this.updatePreference(`iPadOSPatch`,e??null)}})}get letterSpacing(){return new Z({initialValue:this.preferences.letterSpacing,effectiveValue:this.settings.letterSpacing||0,isEffective:this.isDisplayTransformable,onChange:e=>{this.updatePreference(`letterSpacing`,e??null)},supportedRange:ul.range,step:ul.step})}get ligatures(){return new X({initialValue:this.preferences.ligatures,effectiveValue:this.settings.ligatures||!0,isEffective:this.isDisplayTransformable,onChange:e=>{this.updatePreference(`ligatures`,e??null)}})}get lineHeight(){return new Z({initialValue:this.preferences.lineHeight,effectiveValue:this.settings.lineHeight,isEffective:this.isDisplayTransformable,onChange:e=>{this.updatePreference(`lineHeight`,e??null)},supportedRange:dl.range,step:dl.step})}get noRuby(){return new X({initialValue:this.preferences.noRuby,effectiveValue:this.settings.noRuby||!1,isEffective:this.isDisplayTransformable,onChange:e=>{this.updatePreference(`noRuby`,e??null)}})}get paragraphIndent(){return new Z({initialValue:this.preferences.paragraphIndent,effectiveValue:this.settings.paragraphIndent||0,isEffective:this.isDisplayTransformable,onChange:e=>{this.updatePreference(`paragraphIndent`,e??null)},supportedRange:pl.range,step:pl.step})}get paragraphSpacing(){return new Z({initialValue:this.preferences.paragraphSpacing,effectiveValue:this.settings.paragraphSpacing||0,isEffective:this.isDisplayTransformable,onChange:e=>{this.updatePreference(`paragraphSpacing`,e??null)},supportedRange:ml.range,step:ml.step})}get textAlign(){return new Nl({initialValue:this.preferences.textAlign,effectiveValue:this.settings.textAlign||al.start,isEffective:this.isDisplayTransformable,onChange:e=>{this.updatePreference(`textAlign`,e??null)},supportedValues:Object.values(al)})}get textNormalization(){return new X({initialValue:this.preferences.textNormalization,effectiveValue:this.settings.textNormalization||!1,isEffective:this.isDisplayTransformable,onChange:e=>{this.updatePreference(`textNormalization`,e??null)}})}get wordSpacing(){return new Z({initialValue:this.preferences.wordSpacing,effectiveValue:this.settings.wordSpacing||0,isEffective:this.isDisplayTransformable,onChange:e=>{this.updatePreference(`wordSpacing`,e??null)},supportedRange:hl.range,step:hl.step})}get zoom(){return new Z({initialValue:this.preferences.zoom,effectiveValue:this.settings.zoom||1,isEffective:CSS.supports(`zoom`,`1`)??!1,onChange:e=>{this.updatePreference(`zoom`,e??null)},supportedRange:gl.range,step:gl.step})}},Fl=e=>{if(`blob`in e&&e.blob.type)return e.blob.type;if(e.as===`script`)return`text/javascript`;if(e.as===`link`&&`url`in e){let t=e.url.toLowerCase();if(t.endsWith(`.css`))return`text/css`;if([`.js`,`.mjs`,`.cjs`].some(e=>t.endsWith(e)))return`text/javascript`}},Il=(e,t)=>{t.attributes&&Object.entries(t.attributes).forEach(([t,n])=>{t===`type`||t===`rel`||t===`href`||t===`src`||n!=null&&(typeof n==`boolean`?n&&e.setAttribute(t,``):e.setAttribute(t,n))})},Ll=(e,t,n)=>{let r=e.createElement(`script`);r.dataset.readium=`true`,t.id&&(r.id=t.id);let i=t.type||Fl(t);return i&&(r.type=i),Il(r,t),r.src=n,r},Rl=(e,t,n)=>{let r=e.createElement(`link`);r.dataset.readium=`true`,t.id&&(r.id=t.id),t.rel&&(r.rel=t.rel);let i=t.type||Fl(t);return i&&(r.type=i),Il(r,t),r.href=n,r},zl=class{constructor(e){this.blobStore=new Map,this.createdBlobUrls=new Set,this.allowedDomains=[],this.injectableIdCounter=0,this.allowedDomains=(e.allowedDomains||[]).map(e=>{try{return new URL(e),e}catch{throw Error(`Invalid allowed domain: "${e}". Must be a valid URL (e.g., "https://fonts.googleapis.com").`)}}),this.rules=e.rules.map(e=>{let t={...e};return e.prepend&&(t.prepend=e.prepend.map(e=>({...e,id:e.id||`injectable-${this.injectableIdCounter++}`})).reverse()),e.append&&(t.append=e.append.map(e=>({...e,id:e.id||`injectable-${this.injectableIdCounter++}`}))),t})}dispose(){for(let e of this.createdBlobUrls)try{URL.revokeObjectURL(e)}catch(t){console.warn(`Failed to revoke blob URL:`,e,t)}this.createdBlobUrls.clear()}getAllowedDomains(){return[...this.allowedDomains]}async injectForDocument(e,t){for(let n of this.rules)this.matchesRule(n,t)&&await this.applyRule(e,n)}matchesRule(e,t){let n=t.href;return e.resources.some(e=>e instanceof RegExp?e.test(n):n===e)}async getOrCreateBlobUrl(e){let t=e.id;if(this.blobStore.has(t)){let e=this.blobStore.get(t);return e.refCount++,e.url}if(`blob`in e){let n=URL.createObjectURL(e.blob);return this.blobStore.set(t,{url:n,refCount:1}),this.createdBlobUrls.add(n),n}throw Error(`Resource must have a blob property`)}async releaseBlobUrl(e){if(!this.createdBlobUrls.has(e))return;let t=Array.from(this.blobStore.values()).find(t=>t.url===e);if(t&&(t.refCount--,t.refCount<=0)){URL.revokeObjectURL(e),this.createdBlobUrls.delete(e);for(let[t,n]of this.blobStore.entries())if(n.url===e){this.blobStore.delete(t);break}}}async getResourceUrl(e,t){if(`url`in e){let n=new URL(e.url,t.baseURI).toString();if(!this.isValidUrl(n,t))throw Error(`Invalid URL: Only HTTPS, data:, blob:, or localhost HTTP URLs are allowed. Got: ${e.url}`);return n}return this.getOrCreateBlobUrl(e)}createPreloadLink(e,t,n){if(t.as!==`link`||t.rel!==`preload`)return;let r=Rl(e,{...t,rel:`preload`,attributes:{...t.attributes,as:t.as}},n);e.head.appendChild(r)}createElement(e,t,n){if(t.as===`script`)return Ll(e,t,n);if(t.as===`link`)return Rl(e,t,n);throw Error(`Unsupported element type: ${t.as}`)}async applyRule(e,t){let n=[],r=t.prepend?t.prepend.filter(t=>!t.condition||t.condition(e)):[],i=t.append?t.append.filter(t=>!t.condition||t.condition(e)):[];try{for(let t of r)await this.processInjectable(t,e,n,`prepend`);for(let t of i)await this.processInjectable(t,e,n,`append`)}catch(e){for(let{element:e,url:t}of n)try{e.remove(),await this.releaseBlobUrl(t)}catch(e){console.error(`Error during cleanup:`,e)}throw e}}async processInjectable(e,t,n,r){let i=e.target===`body`?t.body:t.head;if(!i)return;let a=null;try{if(a=await this.getResourceUrl(e,t),e.rel===`preload`&&`url`in e)this.createPreloadLink(t,e,a);else{let o=this.createElement(t,e,a);n.push({element:o,url:a}),r===`prepend`?i.prepend(o):i.append(o)}}catch(t){throw console.error(`Failed to process resource:`,t),a&&`blob`in e&&await this.releaseBlobUrl(a),t}}isValidUrl(e,t){try{let n=new URL(e,t.baseURI);if(n.protocol===`data:`||n.protocol===`blob:`&&this.createdBlobUrls.has(e))return!0;if(this.allowedDomains.length>0){let e=n.origin;return this.allowedDomains.some(t=>{let n=new URL(t).origin;return e===n})}return!1}catch{return!1}}},Bl=e=>e.replace(/\/\/.*/g,``).replace(/\/\*[\s\S]*?\*\//g,``).replace(/\n/g,``).replace(/\s+/g,` `),Vl=e=>e.replace(/\/\*(?:(?!\*\/)[\s\S])*\*\/|[\r\n\t]+/g,``).replace(/ {2,}/g,` `),Hl=`/*!
 * Readium CSS v.2.0.5
 * Copyright (c) 2017–2026. Readium Foundation. All rights reserved.
 * Use of this source code is governed by a BSD-style license which is detailed in the
 * LICENSE file present in the project repository where this source code is maintained.
 * Core maintainer: Jiminy Panoz <jiminy.panoz@edrlab.org> 
 * Contributors: 
 * Daniel Weck
 * Hadrien Gardeur
 * Innovimax
 * L. Le Meur
 * Mickaël Menu
 * k_taka
 */

:root[style*="--USER__textAlign"]{
  text-align:var(--USER__textAlign);
}

:root[style*="--USER__textAlign"] body,
:root[style*="--USER__textAlign"] p:not(
  blockquote p,
  figcaption p,
  header p,
  hgroup p,
  :root[style*="readium-experimentalHeaderFiltering-on"] p[class*="title"],
  :root[style*="readium-experimentalHeaderFiltering-on"] div:has(+ *) > h1 + p,
  :root[style*="readium-experimentalHeaderFiltering-on"] div:has(+ *) > p:has(+ h1)
),
:root[style*="--USER__textAlign"] li,
:root[style*="--USER__textAlign"] dd{
  text-align:var(--USER__textAlign) !important;
  -moz-text-align-last:auto !important;
  -epub-text-align-last:auto !important;
  text-align-last:auto !important;
}

:root[style*="--USER__bodyHyphens"]{
  -webkit-hyphens:var(--USER__bodyHyphens) !important;
  -moz-hyphens:var(--USER__bodyHyphens) !important;
  -ms-hyphens:var(--USER__bodyHyphens) !important;
  -epub-hyphens:var(--USER__bodyHyphens) !important;
  hyphens:var(--USER__bodyHyphens) !important;
}

:root[style*="--USER__bodyHyphens"] body,
:root[style*="--USER__bodyHyphens"] p,
:root[style*="--USER__bodyHyphens"] li,
:root[style*="--USER__bodyHyphens"] div,
:root[style*="--USER__bodyHyphens"] dd{
  -webkit-hyphens:var(--USER__bodyHyphens) !important;
  -moz-hyphens:var(--USER__bodyHyphens) !important;
  -ms-hyphens:var(--USER__bodyHyphens) !important;
  -epub-hyphens:var(--USER__bodyHyphens) !important;
  hyphens:var(--USER__bodyHyphens) !important;
}

:root[style*="--USER__fontFamily"]{
  font-family:var(--USER__fontFamily) !important;
}

:root[style*="--USER__fontFamily"] *{
  font-family:revert !important;
}

:root[style*="readium-a11y-on"]{
  font-style:normal !important;
  font-weight:normal !important;
}

:root[style*="readium-a11y-on"] body *:not(code):not(var):not(kbd):not(samp){
  font-family:inherit !important;
  font-style:inherit !important;
  font-weight:inherit !important;
}

:root[style*="readium-a11y-on"] body *:not(a){
  text-decoration:none !important;
}

:root[style*="readium-a11y-on"] body *{
  font-variant-caps:normal !important;
  font-variant-numeric:normal !important;
  font-variant-position:normal !important;
}

:root[style*="readium-a11y-on"] sup,
:root[style*="readium-a11y-on"] sub{
  font-size:1rem !important;
  vertical-align:baseline !important;
}

:root:not([style*="readium-iOSPatch-on"])[style*="--USER__zoom"] body{
  zoom:var(--USER__zoom) !important;
}

:root[style*="readium-iOSPatch-on"][style*="--USER__zoom"] body{
  -webkit-text-size-adjust:var(--USER__zoom) !important;
}

@supports selector(figure:has(> img)){

  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-iOSPatch-on"])[style*="--USER__zoom"] figure:has(> img),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-iOSPatch-on"])[style*="--USER__zoom"] figure:has(> video),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-iOSPatch-on"])[style*="--USER__zoom"] figure:has(> svg),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-iOSPatch-on"])[style*="--USER__zoom"] figure:has(> canvas),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-iOSPatch-on"])[style*="--USER__zoom"] figure:has(> iframe),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-iOSPatch-on"])[style*="--USER__zoom"] figure:has(> audio),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-iOSPatch-on"])[style*="--USER__zoom"] div:has(> img:only-child),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-iOSPatch-on"])[style*="--USER__zoom"] div:has(> video:only-child),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-iOSPatch-on"])[style*="--USER__zoom"] div:has(> svg:only-child),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-iOSPatch-on"])[style*="--USER__zoom"] div:has(> canvas:only-child),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-iOSPatch-on"])[style*="--USER__zoom"] div:has(> iframe:only-child),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-iOSPatch-on"])[style*="--USER__zoom"] div:has(> audio:only-child),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-iOSPatch-on"])[style*="--USER__zoom"] table{
    zoom:calc(100% / var(--USER__zoom)) !important;
  }

  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-iOSPatch-on"])[style*="--USER__zoom"] figcaption,
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-iOSPatch-on"])[style*="--USER__zoom"] caption,
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-iOSPatch-on"])[style*="--USER__zoom"] td,
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-iOSPatch-on"])[style*="--USER__zoom"] th{
    zoom:var(--USER__zoom) !important;
  }
}

:root[style*="--USER__lineHeight"]{
  line-height:var(--USER__lineHeight) !important;
}

:root[style*="--USER__lineHeight"] body,
:root[style*="--USER__lineHeight"] p,
:root[style*="--USER__lineHeight"] li,
:root[style*="--USER__lineHeight"] div{
  line-height:var(--USER__lineHeight) !important;
}

:root[style*="--USER__paraSpacing"] p{
  margin-top:var(--USER__paraSpacing) !important;
  margin-bottom:var(--USER__paraSpacing) !important;
}

:root[style*="--USER__paraIndent"] p:not(
  blockquote p,
  figcaption p,
  header p,
  hgroup p,
  :root[style*="readium-experimentalHeaderFiltering-on"] p[class*="title"],
  :root[style*="readium-experimentalHeaderFiltering-on"] div:has(+ *) > h1 + p,
  :root[style*="readium-experimentalHeaderFiltering-on"] div:has(+ *) > p:has(+ h1)
){
  text-indent:var(--USER__paraIndent) !important;
}

:root[style*="--USER__paraIndent"] p *{
  text-indent:0 !important;
}

:root[style*="--USER__wordSpacing"] h1,
:root[style*="--USER__wordSpacing"] h2,
:root[style*="--USER__wordSpacing"] h3,
:root[style*="--USER__wordSpacing"] h4,
:root[style*="--USER__wordSpacing"] h5,
:root[style*="--USER__wordSpacing"] h6,
:root[style*="--USER__wordSpacing"] p,
:root[style*="--USER__wordSpacing"] li,
:root[style*="--USER__wordSpacing"] div,
:root[style*="--USER__wordSpacing"] dt,
:root[style*="--USER__wordSpacing"] dd{
  word-spacing:var(--USER__wordSpacing) !important;
}

:root[style*="--USER__letterSpacing"] h1,
:root[style*="--USER__letterSpacing"] h2,
:root[style*="--USER__letterSpacing"] h3,
:root[style*="--USER__letterSpacing"] h4,
:root[style*="--USER__letterSpacing"] h5,
:root[style*="--USER__letterSpacing"] h6,
:root[style*="--USER__letterSpacing"] p,
:root[style*="--USER__letterSpacing"] li,
:root[style*="--USER__letterSpacing"] div,
:root[style*="--USER__letterSpacing"] dt,
:root[style*="--USER__letterSpacing"] dd{
  letter-spacing:var(--USER__letterSpacing) !important;
  font-variant:none !important;
}

:root[style*="--USER__fontWeight"] body{
  font-weight:var(--USER__fontWeight) !important;
}

:root[style*="--USER__fontWeight"] b,
:root[style*="--USER__fontWeight"] strong{
  font-weight:bolder;
}

:root[style*="--USER__fontWidth"] body{
  font-stretch:var(--USER__fontWidth) !important;
}

:root[style*="--USER__fontOpticalSizing"] body{
  font-optical-sizing:var(--USER__fontOpticalSizing) !important;
}

:root[style*="readium-noRuby-on"] body rt,
:root[style*="readium-noRuby-on"] body rp{
  display:none;
}

:root[style*="--USER__ligatures"]{
  font-variant-ligatures:var(--USER__ligatures) !important;
}

:root[style*="--USER__ligatures"] *{
  font-variant-ligatures:inherit !important;
}

:root[style*="readium-iPadOSPatch-on"] body{
  -webkit-text-size-adjust:none;
}

:root[style*="readium-iPadOSPatch-on"] p, 
:root[style*="readium-iPadOSPatch-on"] h1, 
:root[style*="readium-iPadOSPatch-on"] h2, 
:root[style*="readium-iPadOSPatch-on"] h3, 
:root[style*="readium-iPadOSPatch-on"] h4, 
:root[style*="readium-iPadOSPatch-on"] h5, 
:root[style*="readium-iPadOSPatch-on"] h6, 
:root[style*="readium-iPadOSPatch-on"] li, 
:root[style*="readium-iPadOSPatch-on"] th, 
:root[style*="readium-iPadOSPatch-on"] td, 
:root[style*="readium-iPadOSPatch-on"] dt, 
:root[style*="readium-iPadOSPatch-on"] dd, 
:root[style*="readium-iPadOSPatch-on"] pre, 
:root[style*="readium-iPadOSPatch-on"] address, 
:root[style*="readium-iPadOSPatch-on"] details, 
:root[style*="readium-iPadOSPatch-on"] summary,
:root[style*="readium-iPadOSPatch-on"] figcaption,
:root[style*="readium-iPadOSPatch-on"] div:not(:has(p, h1, h2, h3, h4, h5, h6, li, th, td, dt, dd, pre, address, aside, details, figcaption, summary)),
:root[style*="readium-iPadOSPatch-on"] aside:not(:has(p, h1, h2, h3, h4, h5, h6, li, th, td, dt, dd, pre, address, aside, details, figcaption, summary)){
  -webkit-text-zoom:reset;
}

:root[style*="readium-iPadOSPatch-on"] abbr, 
:root[style*="readium-iPadOSPatch-on"] b, 
:root[style*="readium-iPadOSPatch-on"] bdi, 
:root[style*="readium-iPadOSPatch-on"] bdo, 
:root[style*="readium-iPadOSPatch-on"] cite, 
:root[style*="readium-iPadOSPatch-on"] code, 
:root[style*="readium-iPadOSPatch-on"] dfn, 
:root[style*="readium-iPadOSPatch-on"] em, 
:root[style*="readium-iPadOSPatch-on"] i, 
:root[style*="readium-iPadOSPatch-on"] kbd, 
:root[style*="readium-iPadOSPatch-on"] mark, 
:root[style*="readium-iPadOSPatch-on"] q, 
:root[style*="readium-iPadOSPatch-on"] rp, 
:root[style*="readium-iPadOSPatch-on"] rt, 
:root[style*="readium-iPadOSPatch-on"] ruby, 
:root[style*="readium-iPadOSPatch-on"] s, 
:root[style*="readium-iPadOSPatch-on"] samp, 
:root[style*="readium-iPadOSPatch-on"] small, 
:root[style*="readium-iPadOSPatch-on"] span, 
:root[style*="readium-iPadOSPatch-on"] strong, 
:root[style*="readium-iPadOSPatch-on"] sub, 
:root[style*="readium-iPadOSPatch-on"] sup, 
:root[style*="readium-iPadOSPatch-on"] time, 
:root[style*="readium-iPadOSPatch-on"] u, 
:root[style*="readium-iPadOSPatch-on"] var{
  -webkit-text-zoom:normal;
}

:root[style*="readium-iPadOSPatch-on"] p:not(:has(b, cite, em, i, q, s, small, span, strong)):first-line{
  -webkit-text-zoom:normal;
}`,Ul='!function(t,e){"object"==typeof exports&&"object"==typeof module?module.exports=e():"function"==typeof define&&define.amd?define([],e):"object"==typeof exports?exports._readium_cssSelectorGenerator=e():t._readium_cssSelectorGenerator=e()}(self,(()=>(()=>{"use strict";var t={d:(e,n)=>{for(var o in n)t.o(n,o)&&!t.o(e,o)&&Object.defineProperty(e,o,{enumerable:!0,get:n[o]})},o:(t,e)=>Object.prototype.hasOwnProperty.call(t,e),r:t=>{"undefined"!=typeof Symbol&&Symbol.toStringTag&&Object.defineProperty(t,Symbol.toStringTag,{value:"Module"}),Object.defineProperty(t,"__esModule",{value:!0})}},e={};function n(t){return"object"==typeof t&&null!==t&&t.nodeType===Node.ELEMENT_NODE}t.r(e),t.d(e,{_readium_cssSelectorGenerator:()=>Z,default:()=>tt,getCssSelector:()=>X});const o={NONE:"",DESCENDANT:" ",CHILD:" > "},r={id:"id",class:"class",tag:"tag",attribute:"attribute",nthchild:"nthchild",nthoftype:"nthoftype"},i="_readium_cssSelectorGenerator";function c(t="unknown problem",...e){console.warn(`${i}: ${t}`,...e)}const s={selectors:[r.id,r.class,r.tag,r.attribute],includeTag:!1,whitelist:[],blacklist:[],combineWithinSelector:!0,combineBetweenSelectors:!0,root:null,maxCombinations:Number.POSITIVE_INFINITY,maxCandidates:Number.POSITIVE_INFINITY,useScope:!1};function u(t){return t instanceof RegExp}function l(t){return["string","function"].includes(typeof t)||u(t)}function a(t){return Array.isArray(t)?t.filter(l):[]}function f(t){const e=[Node.DOCUMENT_NODE,Node.DOCUMENT_FRAGMENT_NODE,Node.ELEMENT_NODE];return function(t){return t instanceof Node}(t)&&e.includes(t.nodeType)}function d(t,e){if(f(t))return t.contains(e)||c("element root mismatch","Provided root does not contain the element. This will most likely result in producing a fallback selector using element\'s real root node. If you plan to use the selector using provided root (e.g. `root.querySelector`), it will not work as intended."),t;const n=e.getRootNode({composed:!1});return f(n)?(n!==document&&c("shadow root inferred","You did not provide a root and the element is a child of Shadow DOM. This will produce a selector using ShadowRoot as a root. If you plan to use the selector using document as a root (e.g. `document.querySelector`), it will not work as intended."),n):S(e)}function m(t){return"number"==typeof t?t:Number.POSITIVE_INFINITY}function p(t=[]){const[e=[],...n]=t;return 0===n.length?e:n.reduce(((t,e)=>t.filter((t=>e.includes(t)))),e)}function g(t){const e=t.map((t=>{if(u(t))return e=>t.test(e);if("function"==typeof t)return e=>{const n=t(e);return"boolean"!=typeof n?(c("pattern matcher function invalid","Provided pattern matching function does not return boolean. It\'s result will be ignored.",t),!1):n};if("string"==typeof t){const e=new RegExp("^"+t.replace(/[|\\\\{}()[\\]^$+?.]/g,"\\\\$&").replace(/\\*/g,".+")+"$");return t=>e.test(t)}return c("pattern matcher invalid","Pattern matching only accepts strings, regular expressions and/or functions. This item is invalid and will be ignored.",t),()=>!1}));return t=>e.some((e=>e(t)))}function h(t,e,n){const o=Array.from(d(n,t[0]).querySelectorAll(e));return o.length===t.length&&t.every((t=>o.includes(t)))}function y(t,e){e=null!=e?e:S(t);const o=[];let r=t;for(;n(r)&&r!==e;)o.push(r),r=r.parentElement;return o}function b(t,e){return p(t.map((t=>y(t,e))))}function S(t){return t.ownerDocument.querySelector(":root")}const N=", ",v=new RegExp(["^$","\\\\s"].join("|")),E=new RegExp(["^$"].join("|")),x=[r.nthoftype,r.tag,r.id,r.class,r.attribute,r.nthchild],w=g(["class","id","ng-*"]);function I({name:t}){return`[${t}]`}function T({name:t,value:e}){return`[${t}=\'${e}\']`}function O({nodeName:t,nodeValue:e}){return{name:F(t),value:F(null!=e?e:void 0)}}function C(t){const e=Array.from(t.attributes).filter((e=>function({nodeName:t,nodeValue:e},n){const o=n.tagName.toLowerCase();return!(["input","option"].includes(o)&&"value"===t||"src"===t&&(null==e?void 0:e.startsWith("data:"))||w(t))}(e,t))).map(O);return[...e.map(I),...e.map(T)]}function j(t){var e;return(null!==(e=t.getAttribute("class"))&&void 0!==e?e:"").trim().split(/\\s+/).filter((t=>!E.test(t))).map((t=>`.${F(t)}`))}function A(t){var e;const n=null!==(e=t.getAttribute("id"))&&void 0!==e?e:"",o=`#${F(n)}`,r=t.getRootNode({composed:!1});return!v.test(n)&&h([t],o,r)?[o]:[]}function R(t){var e;const n=null===(e=t.parentElement)||void 0===e?void 0:e.children;if(n)for(let e=0;e<n.length;e++)if(n[e]===t)return[`:nth-child(${String(e+1)})`];return[]}function $(t){return[F(t.tagName.toLowerCase())]}function D(t){const e=[...new Set((n=t.map($),[].concat(...n)))];var n;return 0===e.length||e.length>1?[]:[e[0]]}function k(t){const e=D([t])[0],n=t.parentElement;if(n){const o=Array.from(n.children).filter((t=>t.tagName.toLowerCase()===e)),r=o.indexOf(t);if(r>-1)return[`${e}:nth-of-type(${String(r+1)})`]}return[]}function*P(t=[],{maxResults:e=Number.POSITIVE_INFINITY}={}){let n=0,o=L(1);for(;o.length<=t.length&&n<e;){n+=1;const e=o.map((e=>t[e]));yield e,o=_(o,t.length-1)}}function _(t=[],e=0){const n=t.length;if(0===n)return[];const o=[...t];o[n-1]+=1;for(let t=n-1;t>=0;t--)if(o[t]>e){if(0===t)return L(n+1);o[t-1]++,o[t]=o[t-1]+1}return o[n-1]>e?L(n+1):o}function L(t=1){return Array.from(Array(t).keys())}const M=":".charCodeAt(0).toString(16).toUpperCase(),V=/[ !"#$%&\'()\\[\\]{|}<>*+,./;=?@^`~\\\\]/;function F(t=""){return CSS?CSS.escape(t):function(t=""){return t.split("").map((t=>":"===t?`\\\\${M} `:V.test(t)?`\\\\${t}`:escape(t).replace(/%/g,"\\\\"))).join("")}(t)}const Y={tag:D,id:function(t){return 0===t.length||t.length>1?[]:A(t[0])},class:function(t){return p(t.map(j))},attribute:function(t){return p(t.map(C))},nthchild:function(t){return p(t.map(R))},nthoftype:function(t){return p(t.map(k))}},G={tag:$,id:A,class:j,attribute:C,nthchild:R,nthoftype:k};function W(t){return t.includes(r.tag)||t.includes(r.nthoftype)?[...t]:[...t,r.tag]}function*q(t,e){const n={};for(const o of t){const t=e[o];t&&t.length>0&&(n[o]=t)}for(const t of function*(t={}){const e=Object.entries(t);if(0===e.length)return;const n=[{index:e.length-1,partial:{}}];for(;n.length>0;){const t=n.pop();if(!t)break;const{index:o,partial:r}=t;if(o<0){yield r;continue}const[i,c]=e[o];for(let t=c.length-1;t>=0;t--)n.push({index:o-1,partial:Object.assign(Object.assign({},r),{[i]:c[t]})})}}(n))yield B(t)}function B(t={}){const e=[...x];return t[r.tag]&&t[r.nthoftype]&&e.splice(e.indexOf(r.tag),1),e.map((e=>{return(o=t)[n=e]?o[n].join(""):"";var n,o})).join("")}function H(t,e){return[...t.map((t=>e+o.DESCENDANT+t)),...t.map((t=>e+o.CHILD+t))]}function*U(t,e,n="",o){const r=function*(t,e){const n=new Set,o=function(t,e){const{blacklist:n,whitelist:o,combineWithinSelector:r,maxCombinations:i}=e,c=g(n),s=g(o);return function(t){const{selectors:e,includeTag:n}=t,o=[...e];return n&&!o.includes("tag")&&o.push("tag"),o}(e).reduce(((e,n)=>{const o=function(t,e){return(0,Y[e])(t)}(t,n),u=function(t=[],e,n){return t.filter((t=>n(t)||!e(t)))}(o,c,s),l=function(t=[],e){return t.sort(((t,n)=>{const o=e(t),r=e(n);return o&&!r?-1:!o&&r?1:0}))}(u,s);return e[n]=r?Array.from(P(l,{maxResults:i})):l.map((t=>[t])),e}),{})}(t,e);for(const t of function*(t,e){for(const n of function(t){const{selectors:e,combineBetweenSelectors:n,includeTag:o,maxCandidates:r}=t,i=n?function(t=[],{maxResults:e=Number.POSITIVE_INFINITY}={}){return Array.from(P(t,{maxResults:e}))}(e,{maxResults:r}):e.map((t=>[t]));return o?i.map(W):i}(e))yield*q(n,t)}(o,e))n.has(t)||(n.add(t),yield t)}(t,o);for(const o of function*(t,e){if(""===e)yield*t;else for(const n of t)yield*H([n],e)}(r,n))h(t,o,e)&&(yield o)}function*z(t,e,n="",o){if(0===t.length)return null;const r=[t.length>1?t:[],...b(t,e).map((t=>[t]))];for(const t of r)for(const r of U(t,e,n,o))yield{foundElements:t,selector:r}}function J(t){return{value:t,include:!1}}function K({selectors:t,operator:e}){let n=[...x];t[r.tag]&&t[r.nthoftype]&&(n=n.filter((t=>t!==r.tag)));let o="";return n.forEach((e=>{var n;(null!==(n=t[e])&&void 0!==n?n:[]).forEach((({value:t,include:e})=>{e&&(o+=t)}))})),e+o}function Q(t,e){return t.map((t=>function(t,e){return[e?":scope":":root",...y(t,e).reverse().map((t=>{var e;const n=function(t,e,n=o.NONE){const r={};return e.forEach((e=>{Reflect.set(r,e,function(t,e){return G[e](t)}(t,e).map(J))})),{element:t,operator:n,selectors:r}}(t,[r.nthchild],o.CHILD);return(null!==(e=n.selectors.nthchild)&&void 0!==e?e:[]).forEach((t=>{t.include=!0})),n})).map(K)].join("")}(t,e))).join(N)}function X(t,e={}){return Z(t,Object.assign(Object.assign({},e),{maxResults:1})).next().value}function*Z(t,e={}){var o;const i=function(t){(t instanceof NodeList||t instanceof HTMLCollection)&&(t=Array.from(t));const e=(Array.isArray(t)?t:[t]).filter(n);return[...new Set(e)]}(t),c=function(t,e={}){const n=Object.assign(Object.assign({},s),e);return{selectors:(o=n.selectors,Array.isArray(o)?o.filter((t=>{return e=r,n=t,Object.values(e).includes(n);var e,n})):[]),whitelist:a(n.whitelist),blacklist:a(n.blacklist),root:d(n.root,t),combineWithinSelector:!!n.combineWithinSelector,combineBetweenSelectors:!!n.combineBetweenSelectors,includeTag:!!n.includeTag,maxCombinations:m(n.maxCombinations),maxCandidates:m(n.maxCandidates),useScope:!!n.useScope,maxResults:m(n.maxResults)};var o}(i[0],e),u=null!==(o=c.root)&&void 0!==o?o:S(i[0]);let l=0;for(const t of function*({elements:t,root:e,rootSelector:n="",options:o}){let r=e,i=n,c=!0;for(;c;){let n=!1;for(const c of z(t,r,i,o)){const{foundElements:o,selector:s}=c;if(n=!0,!h(t,s,e)){r=o[0],i=s;break}yield s}n||(c=!1)}}({elements:i,options:c,root:u,rootSelector:""}))if(yield t,l++,l>=c.maxResults)return;i.length>1&&(yield i.map((t=>X(t,c))).join(N),l++,l>=c.maxResults)||(yield Q(i,c.useScope?u:void 0))}const tt=X;return e})()));',Wl=`// WebPub-specific setup - no execution blocking needed
window._readium_blockedEvents = [];
window._readium_blockEvents = false; // WebPub doesn't need event blocking
window._readium_eventBlocker = null;
`,Gl=`(function() {
    if(window.onload) window.onload = new Proxy(window.onload, {
        apply: function(target, receiver, args) {
            if(!window._readium_blockEvents) {
                Reflect.apply(target, receiver, args);
                return;
            }
            _readium_blockedEvents.push([
                0, target, receiver, args
            ]);
        }
    });
})();
`;function Kl(e){let t=e.filter(e=>e.mediaType.isHTML).map(e=>e.href);return[{resources:t.length>0?t:[/\.html$/,/\.xhtml$/,/\/$/],prepend:[{id:`css-selector-generator`,as:`script`,target:`head`,blob:new Blob([Bl(Ul)],{type:`text/javascript`})},{id:`webpub-execution`,as:`script`,target:`head`,blob:new Blob([Bl(Wl)],{type:`text/javascript`})}],append:[{id:`onload-proxy`,as:`script`,target:`head`,blob:new Blob([Bl(Gl)],{type:`text/javascript`}),condition:e=>!!(e.querySelector(`script`)||e.querySelector(`body[onload]:not(body[onload=''])`))},{id:`readium-css-webpub`,as:`link`,target:`head`,blob:new Blob([Vl(Hl)],{type:`text/css`}),rel:`stylesheet`}]}]}var ql=class{constructor(e){if(this.detectedTools=new Set,!e.onDetected)throw Error(`onDetected callback is required`);this.options=e,this.setupDetection()}isAutomationToolPresent(){let e=window;return e.domAutomation||e.domAutomationController?`Selenium`:navigator.webdriver===!0?`Puppeteer/Playwright`:e.__webdriver_evaluate||e.__selenium_evaluate?`Chrome Automation`:e.callPhantom||e._phantom?`PhantomJS`:e.__nightmare?`Nightmare`:e.$testCafe?`TestCafe`:null}setupDetection(){let e=this.isAutomationToolPresent();e?this.handleDetected(e):(this.observer=new MutationObserver(()=>{let e=this.isAutomationToolPresent();e&&!this.detectedTools.has(e)&&this.handleDetected(e)}),this.observer.observe(document.documentElement,{childList:!0,subtree:!0,attributes:!0}),window.addEventListener(`unload`,()=>this.destroy()))}handleDetected(e){this.detectedTools.add(e),this.options.onDetected?.(e)}destroy(){this.observer?.disconnect(),this.observer=void 0,this.detectedTools.clear()}},Jl=0;function Yl(){return++Jl}var Xl=`
onmessage = function(event) {
  var action = event.data;
  var startTime = performance.now()

  console[action.type](...action.payload);
  postMessage({
    id: action.id,
    time: performance.now() - startTime
  })
}
`,Zl=class{constructor(e,t){this.callbacks=new Map,this.worker=e,this.blobUrl=t,this.worker.onmessage=e=>{let t=e.data,n=t.id,r=this.callbacks.get(t.id);r&&(r({time:t.time}),this.callbacks.delete(n))},this.log=(...e)=>this.send(`log`,...e),this.table=(...e)=>this.send(`table`,...e),this.clear=(...e)=>this.send(`clear`,...e)}async send(e,...t){let n=Yl();return new Promise((r,i)=>{this.callbacks.set(n,r),this.worker.postMessage({id:n,type:e,payload:t}),setTimeout(()=>{i(Error(`timeout`)),this.callbacks.delete(n)},2e3)})}destroy(){this.worker.terminate(),URL.revokeObjectURL(this.blobUrl)}};Zl.workerScript=Xl;var Ql=Zl;function $l(e){return typeof window<`u`&&console?console[e]:(...e)=>{}}var eu=$l(`log`),tu=$l(`table`),nu=$l(`clear`);async function ru(){if(typeof navigator<`u`&&navigator.brave&&navigator.brave.isBrave)try{return await Promise.race([navigator.brave.isBrave(),new Promise(e=>setTimeout(()=>e(!1),1e3))])}catch{return!0}return!1}function iu(e){return!e.excludes.some(e=>e())&&e.includes.some(e=>e())}var au=class{constructor(e={}){if(this.isOpen=!1,this.checkCount=0,this.maxChecks=10,this.maxPrintTime=0,this.largeObjectArray=null,this.options={onDetected:e.onDetected||(()=>{}),onClosed:e.onClosed||(()=>{}),interval:e.interval||1e3,enableDebuggerDetection:e.enableDebuggerDetection||!1},!B.UA.Firefox)try{let e=new Blob([Ql.workerScript],{type:`application/javascript`}),t=URL.createObjectURL(e),n=new Worker(t);this.workerConsole=new Ql(n,t)}catch(e){console.warn(`Failed to create Web Worker for DevTools detection:`,e)}this.startDetection()}createLargeObjectArray(){let e={};for(let t=0;t<500;t++)e[`${t}`]=`${t}`;let t=[];for(let n=0;n<50;n++)t.push(e);return t}getLargeObjectArray(){return this.largeObjectArray===null&&(this.largeObjectArray=this.createLargeObjectArray()),this.largeObjectArray}async calcTablePrintTime(){let e=this.getLargeObjectArray();if(this.workerConsole)try{return(await this.workerConsole.table(e)).time}catch{let t=performance.now();return tu(e),performance.now()-t}{let t=performance.now();return tu(e),performance.now()-t}}async calcLogPrintTime(){let e=this.getLargeObjectArray();if(this.workerConsole)return(await this.workerConsole.log(e)).time;{let t=performance.now();return eu(e),performance.now()-t}}isPerformanceDetectionEnabled(){return iu({includes:[()=>!!B.UA.Chrome,()=>!!B.UA.Chromium,()=>!!B.UA.Safari,()=>!!B.UA.Firefox],excludes:[]})}isDebuggerDetectionEnabled(){return this.options.enableDebuggerDetection}async checkPerformanceBased(){if(!this.isPerformanceDetectionEnabled())return!1;let e=await this.calcTablePrintTime(),t=Math.max(await this.calcLogPrintTime(),await this.calcLogPrintTime());return this.maxPrintTime=Math.max(this.maxPrintTime,t),this.workerConsole?await this.workerConsole.clear():nu(),e===0?!1:this.maxPrintTime===0?!!await ru():e>this.maxPrintTime*10}async checkDebuggerBased(){if(!this.isDebuggerDetectionEnabled()||await ru())return!1;let e=performance.now();try{(()=>{}).constructor(`debugger`)()}catch{}return performance.now()-e>100}async detectDevTools(){return await this.checkPerformanceBased()?!0:this.options.enableDebuggerDetection&&this.checkCount>=this.maxChecks?await this.checkDebuggerBased():!1}startDetection(){this.intervalId=window.setInterval(async()=>{this.checkCount++;let e=await this.detectDevTools();e!==this.isOpen&&(this.isOpen=e,e?this.options.onDetected():this.options.onClosed()),this.checkCount>this.maxChecks*2&&(this.checkCount=0)},this.options.interval),window.addEventListener(`beforeunload`,()=>this.destroy())}isDevToolsOpen(){return this.isOpen}async checkNow(){let e=this.isOpen;return this.isOpen=await this.detectDevTools(),this.isOpen!==e&&(this.isOpen?this.options.onDetected():this.options.onClosed()),this.isOpen}destroy(){this.intervalId&&=(clearInterval(this.intervalId),void 0),this.workerConsole&&=(this.workerConsole.destroy(),void 0),this.isOpen=!1,this.checkCount=0}},ou=class{constructor(e){if(this.detected=!1,!e.onDetected)throw Error(`onDetected callback is required`);this.options=e,this.setupDetection()}isIframed(){try{return window.self===window.top?{isEmbedded:!1,isCrossOrigin:!1}:{isEmbedded:!0,isCrossOrigin:!window.top.location.href}}catch{return{isEmbedded:!0,isCrossOrigin:!0}}}setupDetection(){let{isEmbedded:e,isCrossOrigin:t}=this.isIframed();e?this.handleDetected(t):(this.observer=new MutationObserver(()=>{let{isEmbedded:e,isCrossOrigin:t}=this.isIframed();e&&!this.detected&&(this.handleDetected(t),this.observer?.disconnect())}),this.observer.observe(document.documentElement,{childList:!0,subtree:!0,attributes:!0}),window.addEventListener(`unload`,()=>this.destroy()))}handleDetected(e){this.detected=!0,this.options.onDetected?.(e)}destroy(){this.observer?.disconnect(),this.observer=void 0,this.detected=!1}},su=class{constructor(e={}){this.styleElement=null,this.beforePrintHandler=null,this.onPrintAttempt=e.onPrintAttempt,e.disable&&this.setupPrintProtection(e.watermark)}setupPrintProtection(e){let t=document.createElement(`style`);t.textContent=`
            @media print {
                body * {
                    display: none !important;
                }
                body::after {
                    content: "${e||`Printing has been disabled`}";
                    font-size: 200%;
                    display: block;
                    text-align: center;
                    margin-top: 50vh;
                    transform: translateY(-50%);
                }
            }
        `,document.head.appendChild(t),this.styleElement=t,this.beforePrintHandler=e=>(e.preventDefault(),this.onPrintAttempt?.(),!1),window.addEventListener(`beforeprint`,this.beforePrintHandler)}destroy(){this.beforePrintHandler&&=(window.removeEventListener(`beforeprint`,this.beforePrintHandler),null),this.styleElement?.parentNode&&(this.styleElement.parentNode.removeChild(this.styleElement),this.styleElement=null)}},cu=class{constructor(e={}){this.onContextMenuBlocked=e.onContextMenuBlocked,this.contextMenuHandler=this.handleContextMenu.bind(this),document.addEventListener(`contextmenu`,this.contextMenuHandler,!0),window.addEventListener(`unload`,()=>this.destroy())}handleContextMenu(e){e.preventDefault(),e.stopPropagation();let t={type:`context_menu`,timestamp:Date.now(),clientX:e.clientX,clientY:e.clientY,targetFrameSrc:``};return this.onContextMenuBlocked&&this.onContextMenuBlocked(t),!1}destroy(){this.contextMenuHandler&&=(document.removeEventListener(`contextmenu`,this.contextMenuHandler,!0),void 0)}},lu=`readium:navigator:suspiciousActivity`,uu=class{dispatchSuspiciousActivity(e,t){let n=new CustomEvent(lu,{detail:{type:e,timestamp:Date.now(),...t}});window.dispatchEvent(n)}constructor(e={}){e.monitorDevTools&&(this.devToolsDetector=new au({onDetected:()=>{this.dispatchSuspiciousActivity(`developer_tools`,{targetFrameSrc:``,key:``,code:``,keyCode:-1,ctrlKey:!1,altKey:!1,shiftKey:!1,metaKey:!1})}})),e.checkAutomation&&(this.automationDetector=new ql({onDetected:e=>{this.dispatchSuspiciousActivity(`automation_detected`,{tool:e})}})),e.checkIFrameEmbedding&&(this.iframeEmbeddingDetector=new ou({onDetected:e=>{this.dispatchSuspiciousActivity(`iframe_embedding_detected`,{isCrossOrigin:e})}})),e.protectPrinting?.disable&&(this.printProtector=new su({...e.protectPrinting,onPrintAttempt:()=>{this.dispatchSuspiciousActivity(`print`,{})}})),e.disableContextMenu&&(this.contextMenuProtector=new cu({onContextMenuBlocked:e=>{this.dispatchSuspiciousActivity(`context_menu`,e)}}))}destroy(){this.automationDetector?.destroy(),this.devToolsDetector?.destroy(),this.iframeEmbeddingDetector?.destroy(),this.printProtector?.destroy(),this.contextMenuProtector?.destroy()}},du=`readium:navigator:keyboardPeripheral`,fu=class{constructor(e={}){this.keyManager=new Ms,this.pagehideHandler=e=>{e.persisted||this.destroy()},this.setupKeyboardPeripherals(e.keyboardPeripherals||[])}setupKeyboardPeripherals(e){if(e.length>0){let t=e=>{let t=new CustomEvent(du,{detail:e});window.dispatchEvent(t)};this.keydownHandler=this.keyManager.createUnifiedHandler(``,e,t),this.keydownHandler&&document.addEventListener(`keydown`,this.keydownHandler,!0)}window.addEventListener(`pagehide`,this.pagehideHandler)}destroy(){this.keydownHandler&&=(document.removeEventListener(`keydown`,this.keydownHandler,!0),void 0),window.removeEventListener(`pagehide`,this.pagehideHandler)}},pu=e=>({frameLoaded:e.frameLoaded||(()=>{}),positionChanged:e.positionChanged||(()=>{}),timelineItemChanged:e.timelineItemChanged||(()=>{}),tap:e.tap||(()=>!1),click:e.click||(()=>!1),zoom:e.zoom||(()=>{}),scroll:e.scroll||(()=>{}),customEvent:e.customEvent||(()=>{}),handleLocator:e.handleLocator||(()=>!1),textSelected:e.textSelected||(()=>{}),contentProtection:e.contentProtection||(()=>{}),contextMenu:e.contextMenu||(()=>{}),peripheral:e.peripheral||(()=>{})});function mu(e,t){return e.length===t.length&&e.every((e,n)=>e===t[n])}var hu=class extends Mc{constructor(e,t,n,r=void 0,i={preferences:{},defaults:{}}){super(),this.currentIndex=0,this._destroyed=!1,this._visibleFragmentIds=[],this._notifiedVisibleFragmentIds=[],this._preferencesEditor=null,this._injector=null,this._isNavigating=!1,this._navigatorProtector=null,this._keyboardPeripheralsManager=null,this._suspiciousActivityListener=null,this._keyboardPeripheralListener=null,this._decorations=new Map,this._decorationObservers=new Map,this._decorationHoveredDecorations=new Map,this._decorationActivationState=new Map,this._decorationHoverState=new Map,this._decorationActivationConsumed=!1,this.webViewport={readingOrder:[],progressions:new Map,positions:null},this.pub=t,this.container=e,this.listeners=pu(n),this._preferences=new Al(i.preferences),this._defaults=new jl(i.defaults),this._settings=new Ml(this._preferences,this._defaults,this.hasDisplayTransformability),this._css=new Cl({rsProperties:new Sl({experiments:this._settings.experiments||null}),userProperties:new xl({zoom:this._settings.zoom})});let a=Kl(t.readingOrder.items),o=i.injectables||{rules:[],allowedDomains:[]};if(this._injector=new zl({rules:[...a,...o.rules],allowedDomains:o.allowedDomains}),this._contentProtection=i.contentProtection||{},this._decoratorConfig=i.decoratorConfig||{},this._decorationResizeSelectors=new Set(this._decoratorConfig.resizeWatchSelectors??[]),this._keyboardPeripherals=this.mergeKeyboardPeripherals(this._contentProtection,i.keyboardPeripherals||[]),(this._contentProtection.disableContextMenu||this._contentProtection.checkAutomation||this._contentProtection.checkIFrameEmbedding||this._contentProtection.monitorDevTools||this._contentProtection.protectPrinting?.disable)&&(this._navigatorProtector=new uu(this._contentProtection),this._suspiciousActivityListener=e=>{let{type:t,...n}=e.detail;t===`context_menu`?this.listeners.contextMenu(n):this.listeners.contentProtection(t,n)},window.addEventListener(`readium:navigator:suspiciousActivity`,this._suspiciousActivityListener)),this._keyboardPeripherals.length>0&&(this._keyboardPeripheralsManager=new fu({keyboardPeripherals:this._keyboardPeripherals}),this._keyboardPeripheralListener=e=>{let t=e.detail;this.listeners.peripheral(t)},window.addEventListener(`readium:navigator:keyboardPeripheral`,this._keyboardPeripheralListener)),r&&typeof r.copyWithLocations==`function`){this.currentLocation=r;let e=this.pub.readingOrder.findIndexWithHref(r.href);e>=0&&(this.currentIndex=e)}else this.currentLocation=this.createCurrentLocator()}async load(){if(await this.updateCSS(!1),this._destroyed)return;let e=this.compileCSSProperties(this._css);this.framePool=new qc(this.container,e,this._injector,this._contentProtection,this._keyboardPeripherals,e=>this.pub.timeline.segmentsForHref(e).flatMap(e=>e.references).map(e=>{let t=e.indexOf(`#`);return t>=0?e.slice(t+1):``}).filter(Boolean),[...this._decorationResizeSelectors]),!this._destroyed&&(this.currentLocation=this.completeLocator(this.currentLocation),await this.apply())}get settings(){return Object.freeze({...this._settings})}get preferencesEditor(){return this._preferencesEditor===null&&(this._preferencesEditor=new Pl(this._preferences,this.settings,this.pub.metadata)),this._preferencesEditor}async submitPreferences(e){this._preferences=this._preferences.merging(e),await this.applyPreferences()}async applyPreferences(){this._settings=new Ml(this._preferences,this._defaults,this.hasDisplayTransformability),this._preferencesEditor!==null&&(this._preferencesEditor=new Pl(this._preferences,this.settings,this.pub.metadata)),await this.updateCSS(!0)}async updateCSS(e){this._css.update(this._settings),e&&await this.commitCSS(this._css)}compileCSSProperties(e){let t={};for(let[n,r]of Object.entries(e.rsProperties.toCSSProperties()))t[n]=r;for(let[n,r]of Object.entries(e.userProperties.toCSSProperties()))t[n]=r;return t}async commitCSS(e){let t=this.compileCSSProperties(e);this.framePool.setCSSProperties(t)}get _cframes(){return this.framePool.currentFrames}get hasDisplayTransformability(){return this.pub.metadata?.accessibility?.feature?.some(e=>e.value===x.DISPLAY_TRANSFORMABILITY.value)??!1}eventListener(e,t){switch(e){case`_pong`:this.listeners.frameLoaded(this.framePool.currentFrames[0].iframe.contentWindow),this.listeners.positionChanged(this.currentLocation),this._notifyTimelineChange(this.currentLocation),this._reapplyDecorationsToCurrentFrame();break;case`first_visible_locator`:let n=j.deserialize(t);if(!n)break;this.currentLocation=new j({href:this.currentLocation.href,type:this.currentLocation.type,title:this.currentLocation.title,locations:n?.locations,text:n?.text}),this.listeners.positionChanged(this.currentLocation),this._notifyTimelineChange(this.currentLocation);break;case`text_selected`:{let e=t;e.locator=new j({href:this.currentLocation.href,type:this.currentLocation.type,text:new A({highlight:e.text})}),this.listeners.textSelected(e);break}case`decoration_activated`:this._handleDecorationActivated(t)&&(this._decorationActivationConsumed=!0);break;case`decoration_pointer_enter`:this._handleDecorationPointerEnter(t);break;case`decoration_pointer_leave`:this._handleDecorationPointerLeave(t);break;case`click`:case`tap`:if(this._decorationActivationConsumed){this._decorationActivationConsumed=!1;break}let r=t;if(r.interactiveElement){let e=new DOMParser().parseFromString(r.interactiveElement,`text/html`).body.children[0];if(e.nodeType===e.ELEMENT_NODE&&e.nodeName===`A`&&e.hasAttribute(`href`)){let t=e.attributes.getNamedItem(`href`)?.value;if(t.startsWith(`#`))this.go(this.currentLocation.copyWithLocations({fragments:[t.substring(1)]}),!1,()=>{});else if(t.startsWith(`mailto:`)||t.startsWith(`tel:`))this.listeners.handleLocator(new M({href:t}).locator);else try{let e;if(t.startsWith(`http://`)||t.startsWith(`https://`))e=t;else if(this.currentLocation.href.startsWith(`http://`)||this.currentLocation.href.startsWith(`https://`)){let n=new URL(this.currentLocation.href);e=new URL(t,n).href}else e=Zc.join(Zc.dirname(this.currentLocation.href),t);let n=this.pub.readingOrder.findWithHref(e);n?this.goLink(n,!1,()=>{}):(console.warn(`Internal link not found in readingOrder: ${e}`),this.listeners.handleLocator(new M({href:t}).locator))}catch(e){console.warn(`Couldn't resolve internal link for ${t}: ${e}`),this.listeners.handleLocator(new M({href:t}).locator)}}else console.log(`Clicked on`,e)}else if(e===`click`?this.listeners.click(r):this.listeners.tap(r))break;break;case`scroll`:this.listeners.scroll(t);break;case`zoom`:this.listeners.zoom(t);break;case`progress`:this.syncLocation(t);break;case`content_protection`:let i=t;this.listeners.contentProtection(i.type,i);break;case`context_menu`:this.listeners.contextMenu(t);break;case`keyboard_peripherals`:let a=t,o={...a,interactiveElement:void 0};a.interactiveElement&&(o.interactiveElement=new DOMParser().parseFromString(a.interactiveElement,`text/html`).body.children[0]),this.listeners.peripheral(o);break;case`log`:console.log(this.framePool.currentFrames[0]?.source?.split(`/`)[3],...t);break;default:this.listeners.customEvent(e,t)}}determineModules(){let e=wc.slice(),t=Qc(this.pub.metadata);return t===`cjk-vertical`||t===`mongolian-vertical`?e.map(e=>e===`webpub_snapper`?`cjk_vertical_snapper`:e):e}attachListener(){this.framePool.currentFrames[0]?.msg&&(this.framePool.currentFrames[0].msg.listener=(e,t)=>{this.eventListener(e,t)}),this._reapplyDecorationsToCurrentFrame()}async apply(){if(await this.framePool.update(this.pub,this.currentLocation,this.determineModules()),this.attachListener(),this.pub.readingOrder.findIndexWithHref(this.currentLocation.href)<0)throw Error(`Link for `+this.currentLocation.href+` not found!`)}async destroy(){this._destroyed=!0,this._suspiciousActivityListener&&window.removeEventListener(`readium:navigator:suspiciousActivity`,this._suspiciousActivityListener),this._keyboardPeripheralListener&&window.removeEventListener(`readium:navigator:keyboardPeripheral`,this._keyboardPeripheralListener),this._navigatorProtector?.destroy(),this._keyboardPeripheralsManager?.destroy(),await this.framePool?.destroy(),this._decorations.clear(),this._decorationObservers.clear(),this._decorationHoveredDecorations.clear(),this._decorationActivationState.clear(),this._decorationHoverState.clear(),this._decorationResizeSelectors.clear()}supportsDecorationStyle(e){return Fc(e,this._decoratorConfig.decorationTemplates)}registerDecorationObserver(e,t){this._decorationObservers.has(e)||this._decorationObservers.set(e,new Set),this._decorationObservers.get(e).add(t),t.onDecorationActivated&&(this._decorationActivationState.set(e,!0),this._sendDecorationActivatable(e,!0)),(t.onDecorationPointerEnter||t.onDecorationPointerLeave)&&(this._decorationHoverState.set(e,!0),this._sendDecorationHoverable(e,!0))}unregisterDecorationObserver(e){this._decorationObservers.forEach((t,n)=>{if(!t.has(e))return;t.delete(e);let r=[...t].some(e=>e.onDecorationActivated);this._decorationActivationState.has(n)&&!r&&(this._decorationActivationState.delete(n),this._sendDecorationActivatable(n,!1));let i=[...t].some(e=>e.onDecorationPointerEnter||e.onDecorationPointerLeave);this._decorationHoverState.has(n)&&!i&&(this._decorationHoverState.delete(n),this._sendDecorationHoverable(n,!1))})}_sendDecorationActivatable(e,t){let n=this.framePool?.currentFrames[0];n?.msg&&n.msg.send(`decoration_activatable`,{group:e,activatable:t})}_sendDecorationHoverable(e,t){let n=this.framePool?.currentFrames[0];n?.msg&&n.msg.send(`decoration_hoverable`,{group:e,hoverable:t})}addDecorationResizeTarget(e){this._decorationResizeSelectors.add(e),this.framePool?.addResizeTarget(e)}removeDecorationResizeTarget(e){this._decorationResizeSelectors.delete(e),this.framePool?.removeResizeTarget(e)}applyDecorations(e,t){let n=this._decorations.get(t)??[],r=new Map(n.map(e=>[e.id,e])),i=new Map(e.map(e=>[e.id,e])),a=[],o=[],s=[];for(let[e,t]of r)i.has(e)?zc(t,i.get(e))||s.push(i.get(e)):a.push(e);for(let[e,t]of i)r.has(e)||o.push(t);this._decorations.set(t,e),this._sendDecorationOps(t,a,o,s,n);let c=this._decorationActivationState.get(t);c!==void 0&&this._sendDecorationActivatable(t,c);let l=this._decorationHoverState.get(t);l!==void 0&&this._sendDecorationHoverable(t,l)}_sendDecorationOps(e,t,n,r,i){let a=this.framePool?.currentFrames[0];if(!a?.msg)return;let o=this.currentLocation.href,s=new Map(i.map(e=>[e.id,e]));for(let n of t){let t=s.get(n);!t||t.locator.href!==o||a.msg.send(`decorate`,{group:e,action:`remove`,decoration:{id:n}})}for(let t of n)t.locator.href===o&&a.msg.send(`decorate`,{group:e,action:`add`,decoration:Ic(t,this._decoratorConfig.decorationTemplates)});for(let t of r)t.locator.href===o&&a.msg.send(`decorate`,{group:e,action:`update`,decoration:Ic(t,this._decoratorConfig.decorationTemplates)})}_reapplyDecorationsToCurrentFrame(){let e=this.framePool?.currentFrames[0];if(!e?.msg)return;let t=this.currentLocation.href;for(let[n,r]of this._decorations){let i=r.filter(e=>e.locator.href===t);if(i.length!==0){e.msg.send(`decorate`,{group:n,action:`clear`});for(let t of i)e.msg.send(`decorate`,{group:n,action:`add`,decoration:Ic(t,this._decoratorConfig.decorationTemplates)})}}for(let[t,n]of this._decorationActivationState)e.msg.send(`decoration_activatable`,{group:t,activatable:n});for(let[t,n]of this._decorationHoverState)e.msg.send(`decoration_hoverable`,{group:t,hoverable:n})}_handleDecorationActivated(e){let t=this._decorationObservers.get(e.group);if(!t||t.size===0)return!1;let n=(this._decorations.get(e.group)??[]).find(t=>t.id===e.decorationId);if(!n)return!1;let r={decoration:n,group:e.group,rect:e.rect,point:e.point},i=!1;for(let e of t)e.onDecorationActivated?.(r)&&(i=!0);return i}_handleDecorationPointerEnter(e){let t=this._decorationObservers.get(e.group);if(!t||t.size===0)return;let n=(this._decorations.get(e.group)??[]).find(t=>t.id===e.decorationId);if(!n)return;this._decorationHoveredDecorations.set(e.group,n);let r={decoration:n,group:e.group,rect:e.rect,point:e.point};for(let e of t)e.onDecorationPointerEnter?.(r)}_handleDecorationPointerLeave(e){let t=this._decorationObservers.get(e.group);if(!t||t.size===0)return;let n=(this._decorations.get(e.group)??[]).find(t=>t.id===e.decorationId)??this._decorationHoveredDecorations.get(e.group);if(this._decorationHoveredDecorations.delete(e.group),!n)return;let r={decoration:n,group:e.group,rect:e.rect,point:e.point};for(let e of t)e.onDecorationPointerLeave?.(r)}async changeResource(e){if(e===0)return!1;let t=this.pub.readingOrder.findIndexWithHref(this.currentLocation.href),n=Math.max(0,Math.min(this.pub.readingOrder.items.length-1,t+e));return n!==t&&(this.currentIndex=n,this.currentLocation=this.createCurrentLocator(),await this.apply(),!0)}updateViewport(e){this.webViewport.readingOrder=[],this.webViewport.progressions.clear(),this.webViewport.positions=null,this.currentLocation&&(this.webViewport.readingOrder.push(this.currentLocation.href),this.webViewport.progressions.set(this.currentLocation.href,e),this.currentLocation.locations?.position!==void 0&&(this.webViewport.positions=[this.currentLocation.locations.position]))}async syncLocation(e){let t=e;this.currentLocation&&=this.currentLocation.copyWithLocations({progression:t.start}),this.updateViewport(t),this.listeners.positionChanged(this.currentLocation);let n=t.fragmentId?this.currentLocation.copyWithLocations({fragments:[`#${t.fragmentId}`]}):this.currentLocation;this._visibleFragmentIds=t.visibleFragmentIds??[],this._notifyTimelineChange(n),await this.framePool.update(this.pub,this.currentLocation,this.determineModules())}goBackward(e,t){this._isNavigating?t(!1):(this._isNavigating=!0,this.changeResource(-1).then(e=>{this._isNavigating=!1,t(e)}))}goForward(e,t){this._isNavigating?t(!1):(this._isNavigating=!0,this.changeResource(1).then(e=>{this._isNavigating=!1,t(e)}))}get currentLocator(){return this.currentLocation}get viewport(){return this.webViewport}get isScrollStart(){let e=this.viewport.readingOrder[0];return this.viewport.progressions.get(e)?.start===0}get isScrollEnd(){let e=this.viewport.readingOrder[this.viewport.readingOrder.length-1];return this.viewport.progressions.get(e)?.end===1}get canGoBackward(){let e=this.pub.readingOrder.items[0]?.href;return!(this.viewport.progressions.has(e)&&this.viewport.progressions.get(e)?.start===0)}get canGoForward(){let e=this.pub.readingOrder.items[this.pub.readingOrder.items.length-1]?.href;return!(this.viewport.progressions.has(e)&&this.viewport.progressions.get(e)?.end===1)}get readingProgression(){return this.pub.metadata.effectiveReadingProgression}get publication(){return this.pub}get timeline(){let e=this.pub.timeline;return this._wrappedTimeline||=new Proxy(e,{get:(e,t)=>{if(t!==`navigableFrom`){let n=Reflect.get(e,t,e);return typeof n==`function`?n.bind(e):n}return t=>{let n=this._visibleFragmentIds,r=(n.length?e.locate(this.currentLocation.copyWithLocations({fragments:[`#${n[0]}`]})):void 0)??t,i=(n.length?e.locate(this.currentLocation.copyWithLocations({fragments:[`#${n[n.length-1]}`]})):void 0)??t;if(this.isScrollStart){let t=e.ancestors(r).find(e=>e.references.includes(this.currentLocation.href));t&&(r=t)}return{previous:e.navigableFrom(r).previous,next:e.navigableFrom(i).next}}}}),this._wrappedTimeline}async loadLocator(e,t){let n=!1,r=Nt(e.locations);if(e.text?.highlight?n=await new Promise((t,n)=>{this.framePool.currentFrames[0].msg.send(`go_text`,r?[e.text?.serialize(),r]:e.text?.serialize(),e=>t(e))}):r&&(n=await new Promise((e,t)=>{this.framePool.currentFrames[0].msg.send(`go_text`,[``,r],t=>e(t))})),n){t(n);return}let i=Rt(e.locations);if(i&&(n=await new Promise((e,t)=>{this.framePool.currentFrames[0].msg.send(`go_id`,i,t=>e(t))})),n){t(n);return}let a=e?.locations?.progression;n=a&&a>0?await new Promise((e,t)=>{this.framePool.currentFrames[0].msg.send(`go_progression`,a,t=>e(t))}):!0,t(n)}completeLocator(e){if(!e.href){let t=this.pub.readingOrder.items,n=!1;if(typeof e.locations.position==`number`){let r=t[e.locations.position-1];r&&(e=(this.pub.manifest.locatorFromLink(r)||new j({href:r.href,type:r.type||`text/html`})).copyWithLocations(e.locations),n=!0)}if(!n&&typeof e.locations?.totalProgression==`number`){let n=e.locations.totalProgression,r=t[Math.min(t.length-1,Math.max(0,Math.round(n*(t.length-1))))];r&&(e=(this.pub.manifest.locatorFromLink(r)||new j({href:r.href,type:r.type||`text/html`})).copyWithLocations(e.locations))}}return e}go(e,t,n){e=this.completeLocator(e);let r=e.href.split(`#`)[0];if(!this.pub.readingOrder.findWithHref(r))return n(this.listeners.handleLocator(e));let i=this.pub.readingOrder.findIndexWithHref(r);i>=0&&(this.currentIndex=i),this._isNavigating?n(!1):(this._isNavigating=!0,this.currentLocation=this.createCurrentLocator(),this.apply().then(()=>this.loadLocator(e,e=>{this._isNavigating=!1,n(e)})).then(()=>{this.attachListener()}))}goLink(e,t,n){return this.go(e.locator,t,n)}createCurrentLocator(){let e=this.pub.readingOrder.items[this.currentIndex];if(!e)throw Error(`No current resource available`);let t=this.currentLocation&&this.currentLocation.href===e.href&&this.currentLocation.locations.progression?this.currentLocation.locations.progression:0;return this.pub.manifest.locatorFromLink(e)||new j({href:e.href,type:e.type||`text/html`,locations:new k({fragments:[],progression:t,position:this.currentIndex+1})})}_notifyTimelineChange(e){let t=this.timeline.locate(e),n=!mu(this._visibleFragmentIds,this._notifiedVisibleFragmentIds);(t!==this._currentTimelineItem||n)&&(this._currentTimelineItem=t,this._notifiedVisibleFragmentIds=this._visibleFragmentIds,this.listeners.timelineItemChanged(t))}},gu=hu,_u=e=>e.split(/[?#]/)[0],vu=e=>{let t=_u(e);if(t.endsWith(`/`))return t;try{let e=new URL(t);return e.pathname=e.pathname.substring(0,e.pathname.lastIndexOf(`/`)+1),e.href}catch{return t.replace(/[^/]*$/,``)}},yu=(e,t=`always`,n)=>{let r=t===`always`||t!==`never`&&typeof n==`string`&&n.startsWith(`https:`),i=e.join(` `);return[...r?[`upgrade-insecure-requests`]:[],`default-src ${i} blob:`,`connect-src 'none'`,`script-src ${i} blob: 'unsafe-inline'`,`style-src ${i} blob: 'unsafe-inline'`,`img-src ${i} blob: data:`,`font-src ${i} blob: data:`,`object-src ${i} blob:`,`child-src ${i}`,`form-action 'none'`].join(`; `)},bu=class{constructor(e,t,n,r){this.pub=e,this.baseURL=t,this.item=n,this.injector=null,this.item=n,this.cssProperties=r.cssProperties,this.injector=r.injector??null,this.upgradeInsecureRequests=r.upgradeInsecureRequests??`always`}reset(){this.currentUrl&&URL.revokeObjectURL(this.currentUrl),this.currentUrl=void 0,this.currentResource?.close(),this.currentResource=void 0,this.pendingBuild=void 0}async build(e=!1){if(this.currentUrl)return this.currentUrl;if(this.pendingBuild)return this.pendingBuild;let t=this.doBuild(e).finally(()=>{this.pendingBuild===t&&(this.pendingBuild=void 0)});return this.pendingBuild=t,t}async doBuild(e){this.currentResource=this.pub.get(this.item);let t=await this.currentResource.link();if(!this.currentResource)return`about:blank`;if(t.mediaType.isHTML){let t=await this.buildHtmlFrame(e);return this.currentUrl=t,t}if(t.mediaType.isBitmap||t.mediaType.equals(Ht.SVG)){let e=await this.buildImageFrame();return this.currentUrl=e,e}throw Error(`Unsupported frame mediatype `+t.mediaType.string)}async buildHtmlFrame(e=!1){if(!this.currentResource)throw Error(`No resource loaded`);let t=await this.currentResource.link(),n=await this.currentResource.readAsXML();if(!n)throw Error(`Failed reading item ${t.href}`);let r=n.querySelector(`parsererror`);if(r){let e=r.querySelector(`div`);throw Error(`Failed parsing item ${t.href}: ${e?.textContent||r.textContent}`)}return this.injector&&await this.injector.injectForDocument(n,t),this.finalizeDOM(n,this.pub.baseURL,t.toURL(this.baseURL)||``,t.mediaType,e,this.cssProperties,this.upgradeInsecureRequests)}async buildImageFrame(){if(!this.currentResource)throw Error(`No resource loaded`);let e=await this.currentResource.link(),t=e.toURL(this.baseURL)||``,n=document.implementation.createHTMLDocument(e.title||e.href);if((e?.height||0)>0&&(e?.width||0)>0){let t=n.createElement(`meta`);t.name=`viewport`,t.content=`width=${e.width}, height=${e.height}`,t.dataset.readium=`true`,n.head.appendChild(t)}let r=document.createElement(`img`);r.src=t||``,r.alt=e.title||``,await r.decode(),n.body.appendChild(r),this.injector&&await this.injector.injectForDocument(n,new M({href:`readium-image-frame.xhtml`,type:Ht.XHTML.string}));let i=n.createElement(`style`);return i.dataset.readium=`true`,i.textContent=`
        html, body { width: 100%; height: 100%; margin: 0; padding: 0; font-size: 0; }
        img { margin: 0; padding: 0; border: 0; }`,n.head.appendChild(i),this.finalizeDOM(n,this.pub.baseURL,t,e.mediaType,!0,void 0,this.upgradeInsecureRequests)}setProperties(e,t){for(let n in e){let r=e[n];r&&t.documentElement.style.setProperty(n,r)}}finalizeDOM(e,t,n,r,i=!1,a,o=`always`){if(!e)return``;let s=(this.injector?.getAllowedDomains?.()||[]).map(_u),c=t?vu(t):void 0,l=[...new Set([...c?[c]:[],...s])].filter(Boolean);if(a&&!i&&this.setProperties(a,e),e.body.querySelectorAll(`img`).forEach(e=>{e.setAttribute(`fetchpriority`,`high`),e.setAttribute(`referrerpolicy`,`origin`)}),r.isHTML&&this.pub.metadata.languages?.[0]){let t=this.pub.metadata.languages[0];if(r===Ht.XHTML){let n=e.documentElement.lang||e.documentElement.getAttribute(`xml:lang`),r=e.body.lang||e.body.getAttribute(`xml:lang`);r&&!n?(e.documentElement.lang=r,e.documentElement.setAttribute(`xml:lang`,r),e.body.removeAttribute(`xml:lang`),e.body.removeAttribute(`lang`)):n||(e.documentElement.lang=t,e.documentElement.setAttribute(`xml:lang`,t))}else r===Ht.HTML&&!e.documentElement.lang&&(e.documentElement.lang=t)}if(Qc(this.pub.metadata)===`rtl`&&!e.documentElement.dir&&!e.body.dir&&(e.documentElement.dir=R.rtl),n!==void 0){let t=e.createElement(`base`);t.href=n,t.dataset.readium=`true`,e.head.firstChild.before(t)}let u=e.createElement(`meta`);return u.httpEquiv=`Content-Security-Policy`,u.content=yu(l,o,t),u.dataset.readium=`true`,e.head.firstChild.before(u),URL.createObjectURL(new Blob([new XMLSerializer().serializeToString(e)],{type:r.isHTML?r.string:`application/xhtml+xml`}))}},xu=class{constructor(e,t={},n=[],r=[],i=[]){this.timelineFragmentIds=r,this.hidden=!0,this.destroyed=!1,this.pendingUnwatchSelectors=[],this.currModules=[],this.serialize=Gc(),this.frame=document.createElement(`iframe`),this.frame.sandbox.value=`allow-same-origin allow-scripts`,this.frame.classList.add(`readium-navigator-iframe`),this.frame.style.visibility=`hidden`,this.frame.ariaHidden=`true`,this.frame.style.opacity=`0`,this.frame.style.position=`absolute`,this.frame.style.pointerEvents=`none`,this.frame.style.transition=`visibility 0s, opacity 0.1s linear`,this.source=e,this.contentProtectionConfig={...t},this.keyboardPeripheralsConfig=[...n],this.resizeWatchSelectors=[...i]}async load(e){return this.serialize(()=>new Promise((t,n)=>{if(this.loader){let n=this.frame.contentWindow;if([...this.currModules].sort().join(`|`)===[...e].sort().join(`|`)){try{t(n)}catch{}return}this.comms?.halt(),this.loader.destroy(),this.loader=new Ec(n,e),this.currModules=e,this.comms=void 0;try{t(n)}catch{}}else this.frame.onload=()=>{let n=this.frame.contentWindow;this.loader=new Ec(n,e),this.currModules=e;try{t(n)}catch{}},this.frame.onerror=e=>{try{n(e)}catch{}},this.frame.contentWindow.location.replace(this.source)}))}applyContentProtection(){this.comms||this.comms.resume(),this.comms.send(`peripherals_protection`,this.contentProtectionConfig),this.keyboardPeripheralsConfig&&this.keyboardPeripheralsConfig.length>0&&(this.conditionBridge?.destroy(),this.conditionBridge=new Wc(this.keyboardPeripheralsConfig,e=>{e.length>0&&this.comms.send(`keyboard_peripherals`,e)}),this.conditionBridge.setup()),this.contentProtectionConfig.monitorScrollingExperimental&&this.comms.send(`scroll_protection`,{}),this.contentProtectionConfig.protectPrinting?.disable&&this.comms.send(`print_protection`,this.contentProtectionConfig.protectPrinting),this.resizeWatchSelectors.forEach(e=>{this.comms.send(`decoration_resize`,{action:`watch`,selector:e})}),this.pendingUnwatchSelectors.forEach(e=>{this.comms.send(`decoration_resize`,{action:`unwatch`,selector:e})}),this.pendingUnwatchSelectors=[]}addResizeTarget(e){this.resizeWatchSelectors.includes(e)||this.resizeWatchSelectors.push(e),this.pendingUnwatchSelectors=this.pendingUnwatchSelectors.filter(t=>t!==e),this.comms?.ready&&this.comms.send(`decoration_resize`,{action:`watch`,selector:e})}removeResizeTarget(e){this.resizeWatchSelectors=this.resizeWatchSelectors.filter(t=>t!==e),this.comms?.ready?this.comms.send(`decoration_resize`,{action:`unwatch`,selector:e}):this.pendingUnwatchSelectors.includes(e)||this.pendingUnwatchSelectors.push(e)}async destroy(){return this.serialize(async()=>{this.conditionBridge?.destroy(),await this.hideNow(),this.loader?.destroy(),this.frame.remove(),this.destroyed=!0})}async hide(){return this.serialize(()=>this.hideNow())}async hideNow(){if(!this.destroyed){if(this.frame.style.visibility=`hidden`,this.frame.ariaHidden=`true`,this.frame.style.opacity=`0`,this.frame.style.pointerEvents=`none`,this.hidden=!0,this.frame.blur(),this.frame.parentElement)return this.comms===void 0||!this.comms.ready?void 0:new Promise((e,t)=>{this.comms?.send(`unfocus`,void 0,t=>{this.comms?.halt(),e()})});this.comms?.halt()}}async show(e){return this.serialize(()=>this.showNow(e))}async showNow(e){if(this.destroyed)throw Error(`Trying to show frame when it doesn't exist`);if(!this.frame.parentElement)throw Error(`Trying to show frame that is not attached to the DOM`);return this.comms?this.comms.resume():this.comms=new Uc(this.frame.contentWindow,this.source),new Promise((t,n)=>{this.comms?.send(`activate`,void 0,()=>{this.comms?.send(`focus`,void 0,()=>{this.applyContentProtection(),this.timelineFragmentIds.length>0&&this.comms?.send(`timeline_entries`,this.timelineFragmentIds);let n=()=>{this.frame.style.removeProperty(`visibility`),this.frame.style.removeProperty(`opacity`),this.frame.style.removeProperty(`pointer-events`),this.frame.ariaHidden=null,this.hidden=!1,B.UA.WebKit&&this.comms?.send(`force_webkit_recalc`,void 0),t()};e===void 0?n():this.comms?.send(`go_progression`,e,n)})})})}setCSSProperties(e){this.destroyed||!this.frame.contentWindow||(this.hidden&&!this.comms&&(this.comms=new Uc(this.frame.contentWindow,this.source),this.comms.halt()),this.comms?.send(`update_properties`,e))}get iframe(){if(this.destroyed)throw Error(`Trying to use frame when it doesn't exist`);return this.frame}get realSize(){if(this.destroyed)throw Error(`Trying to use frame client rect when it doesn't exist`);return this.frame.getBoundingClientRect()}get isDestroyed(){return this.destroyed}get window(){if(this.destroyed||!this.frame.contentWindow)throw Error(`Trying to use frame window when it doesn't exist`);return this.frame.contentWindow}get atLeft(){return this.window.scrollX<5}get atRight(){return this.window.scrollX>this.window.document.scrollingElement.scrollWidth-this.window.innerWidth-5}get msg(){return this.comms}get ldr(){return this.loader}},Su=10,Cu=5,wu=class{constructor(e,t,n,r,i,a,o,s=[],c){this.pool=new Map,this.blobs=new Map,this.inprogress=new Map,this.pendingUpdates=new Map,this.injector=null,this.updateSequence=0,this.container=e,this.positions=t,this.currentCssProperties=n,this.injector=r??null,this.contentProtectionConfig=i||{},this.keyboardPeripheralsConfig=a||[],this.getFragmentIds=o??(()=>[]),this.resizeWatchSelectors=[...s],this.upgradeInsecureRequests=c??`always`}addResizeTarget(e){this.resizeWatchSelectors.includes(e)||this.resizeWatchSelectors.push(e),this.pool.forEach(t=>t.addResizeTarget(e))}removeResizeTarget(e){this.resizeWatchSelectors=this.resizeWatchSelectors.filter(t=>t!==e),this.pool.forEach(t=>t.removeResizeTarget(e))}async destroy(){let e=this.inprogress.values(),t=e.next(),n=[];for(;t.value;)n.push(t.value),t=e.next();n.length>0&&await Promise.allSettled(n),this.inprogress.clear();let r=this.pool.values(),i=r.next();for(;i.value;)await i.value.destroy(),i=r.next();this.pool.clear(),this.blobs.forEach(e=>e.reset()),this.blobs.clear(),this.injector?.dispose(),this.container.childNodes.forEach(e=>{(e.nodeType===Node.ELEMENT_NODE||e.nodeType===Node.TEXT_NODE)&&e.remove()})}async update(e,t,n,r=!1){for(;this.forcedUpdate;)await this.forcedUpdate;let i=++this.updateSequence,a=this.positions.findIndex(e=>e.locations.position===t.locations.position);if(a<0)throw Error(`Locator not found in position list: ${t.locations.position} > ${this.positions.reduce((e,t)=>t.locations.position||0>e?t.locations.position||0:e,0)}`);let o=this.positions[a].href;this.inprogress.has(o)&&await this.inprogress.get(o);let s=new Promise(async(s,c)=>{let l=[],u=[];this.positions.forEach((e,t)=>{(t>a+Su||t<a-Su)&&(l.includes(e.href)||l.push(e.href)),t<a+Cu&&t>a-Cu&&(u.includes(e.href)||u.push(e.href))}),l.forEach(async e=>{u.includes(e)||this.pool.has(e)&&(await this.pool.get(e)?.destroy(),this.pool.delete(e),this.pendingUpdates.has(e)&&this.pendingUpdates.set(e,{inPool:!1}))}),this.currentBaseURL!==void 0&&e.baseURL!==this.currentBaseURL&&(this.blobs.forEach(e=>e.reset()),this.blobs.clear()),this.currentBaseURL=e.baseURL,r&&(this.blobs.forEach(e=>e.reset()),this.blobs.clear(),this.pendingUpdates.clear());let d=async t=>{if(this.pendingUpdates.has(t)&&this.pendingUpdates.get(t)?.inPool===!1){let e=this.blobs.get(t);e&&(e.reset(),this.blobs.delete(t),this.pendingUpdates.delete(t))}if(this.pool.has(t)){let e=this.pool.get(t);if(!this.blobs.has(t))await e.destroy(),this.pool.delete(t),this.pendingUpdates.delete(t);else{await e.load(n);return}}let r=e.readingOrder.findWithHref(t);if(!r)return;this.blobs.has(t)||this.blobs.set(t,new bu(e,this.currentBaseURL||``,r,{cssProperties:this.currentCssProperties,injector:this.injector,upgradeInsecureRequests:this.upgradeInsecureRequests}));let i=new xu(await this.blobs.get(t).build(),this.contentProtectionConfig,this.keyboardPeripheralsConfig,this.getFragmentIds(t),this.resizeWatchSelectors);return t!==o&&await i.hide(),this.container.appendChild(i.iframe),await i.load(n),this.pool.set(t,i),i};try{await Promise.all(u.filter(e=>e===o).map(e=>d(e)))}catch(e){c(e);return}if(i!==this.updateSequence){s();return}Promise.all(u.filter(e=>e!==o&&!this.inprogress.has(e)).map(async e=>{let t=d(e);this.inprogress.set(e,t);try{await t}finally{this.inprogress.get(e)===t&&this.inprogress.delete(e)}})).catch(e=>console.warn(`Failed preloading frame`,e));let f=this.pool.get(o);if(!f)s();else{if(f?.source!==this._currentFrame?.source||r){if(await this._currentFrame?.hide(),i!==this.updateSequence){s();return}let e=this.pool.get(o);if(!e||(await e.load(n),i!==this.updateSequence)){s();return}let r=this.pool.get(o);if(!r){s();return}if(await r.show(t.locations.progression),this._currentFrame=r,f){let e=this.container.ownerDocument.activeElement;e&&e.tagName===`IFRAME`&&e!==f.iframe&&f.iframe.focus({preventScroll:!0})}}s()}});if(this.inprogress.set(o,s),r){let e=s.catch(()=>{});this.forcedUpdate=e,e.then(()=>{this.forcedUpdate===e&&(this.forcedUpdate=void 0)})}try{await s}finally{this.inprogress.delete(o)}}setCSSProperties(e){if(!((e,t)=>{let n=Object.keys(e),r=Object.keys(t);if(n.length!==r.length)return!1;for(let r of n)if(e[r]!==t[r])return!1;return!0})(this.currentCssProperties||{},e)){this.currentCssProperties=e,this.pool.forEach(t=>{t.setCSSProperties(e)});for(let e of this.blobs.keys())this.pendingUpdates.set(e,{inPool:this.pool.has(e)})}}get currentFrames(){return[this._currentFrame]}get currentBounds(){let e={x:0,y:0,width:0,height:0,top:0,right:0,bottom:0,left:0,toJSON(){return this}};return this.currentFrames.forEach(t=>{if(!t)return;let n=t.realSize;e.x=Math.min(e.x,n.x),e.y=Math.min(e.y,n.y),e.width+=n.width,e.height=Math.max(e.height,n.height),e.top=Math.min(e.top,n.top),e.right=Math.min(e.right,n.right),e.bottom=Math.min(e.bottom,n.bottom),e.left=Math.min(e.left,n.left)}),e}},Tu=(e=>(e[e.Left=0]=`Left`,e[e.Center=1]=`Center`,e[e.Right=2]=`Right`,e))(Tu||{}),Eu=(e=>(e[e.Top=0]=`Top`,e[e.Middle=1]=`Middle`,e[e.Bottom=2]=`Bottom`,e))(Eu||{}),Du=class{constructor(){this.outerWidth=0,this.outerHeight=0,this.HTML=document.documentElement,this.Head=document.head,this.Body=document.body}refreshOuterPixels(e){B.OS.iOS||(this.outerHeight=window.outerHeight-window.innerHeight,B.OS.Android&&B.UA.Chrome&&window.screen.height>window.innerHeight&&(this.outerHeight=(window.screen.height-window.innerHeight)/1.5),this.outerWidth=window.outerWidth-window.innerWidth)}getBibiEventCoord(e,t=0){let n={X:0,Y:0};return/^touch/.test(e.type)?(n.X=e.touches[t].screenX,n.Y=e.touches[t].screenY):(n.X=e.screenX,n.Y=e.screenY),(e.target.ownerDocument?.documentElement||e.target.documentElement)===this.HTML&&(n.X-=this.HTML.scrollLeft+this.Body.scrollLeft,n.Y-=this.HTML.scrollTop+this.Body.scrollTop),n.X-=this.outerWidth,n.Y-=this.outerHeight,n}getTouchDistance(e){if(e.touches.length!==2)return 0;let t=e.touches[0].screenX-this.outerWidth,n=e.touches[0].screenY-this.outerHeight,r=e.touches[1].screenX-this.outerWidth,i=e.touches[1].screenY-this.outerHeight;return Math.sqrt((r-t)**2+(i-n)**2)}getTouchCenter(e){if(e.touches.length!==2)return null;let t=this.HTML.scrollLeft+this.Body.scrollLeft,n=this.HTML.scrollTop+this.Body.scrollTop,r=e.touches[0].screenX-this.outerWidth-t,i=e.touches[0].screenY-this.outerHeight-n,a=e.touches[1].screenX-this.outerWidth-t,o=e.touches[1].screenY-this.outerHeight-n;return{X:(r+a)/2,Y:(i+o)/2}}getBibiEvent(e){if(!e)return{Coord:null,Division:null,Ratio:null,Target:null};let t=this.getBibiEventCoord(e),n={X:t.X/window.innerWidth,Y:t.Y/window.innerHeight},r,i,a,o;a=r=.3,o=i=.7;let s={X:null,Y:null};return s.X=n.X<a?0:o<n.X?2:1,s.Y=n.Y<r?0:i<n.Y?2:1,{Target:e.target,Coord:t,Ratio:n,Division:s}}},Ou=class{constructor(){this._DOM={show:!1,pinchTarget:document.createElement(`div`),touch1:document.createElement(`div`),touch2:document.createElement(`div`),center:document.createElement(`div`),stats:document.createElement(`div`)},this._DOM.show=!0,this._DOM.pinchTarget.style.zIndex=this._DOM.stats.style.zIndex=this._DOM.center.style.zIndex=this._DOM.touch1.style.zIndex=this._DOM.touch2.style.zIndex=`100000`,this._DOM.pinchTarget.style.position=this._DOM.stats.style.position=this._DOM.center.style.position=this._DOM.touch1.style.position=this._DOM.touch2.style.position=`absolute`,this._DOM.pinchTarget.style.borderRadius=this._DOM.center.style.borderRadius=this._DOM.touch1.style.borderRadius=this._DOM.touch2.style.borderRadius=`50%`,this._DOM.pinchTarget.style.pointerEvents=this._DOM.stats.style.pointerEvents=this._DOM.center.style.pointerEvents=this._DOM.touch1.style.pointerEvents=this._DOM.touch2.style.pointerEvents=`none`,this._DOM.pinchTarget.style.display=this._DOM.center.style.display=this._DOM.touch1.style.display=this._DOM.touch2.style.display=`none`,this._DOM.pinchTarget.style.paddingTop=this._DOM.center.style.paddingTop=`10px`,this._DOM.pinchTarget.style.width=this._DOM.pinchTarget.style.height=this._DOM.center.style.width=this._DOM.center.style.height=`10px`,this._DOM.pinchTarget.style.backgroundColor=`green`,this._DOM.center.style.backgroundColor=`red`,this._DOM.touch1.style.backgroundColor=this._DOM.touch2.style.backgroundColor=`blue`,this._DOM.touch1.style.height=this._DOM.touch2.style.height=`20px`,this._DOM.touch1.style.width=this._DOM.touch2.style.width=`20px`,this._DOM.touch1.style.paddingTop=this._DOM.touch2.style.paddingTop=`20px`,this._DOM.touch1.textContent=`1`,this._DOM.touch2.textContent=`2`,this._DOM.stats.style.padding=`20px`,this._DOM.stats.style.backgroundColor=`rgba(0,0,0,0.5)`,this._DOM.stats.style.color=`white`,this._DOM.stats.textContent=`[stats]`,document.body.appendChild(this._DOM.stats),document.body.appendChild(this._DOM.center),document.body.appendChild(this._DOM.touch1),document.body.appendChild(this._DOM.touch2),document.body.appendChild(this._DOM.pinchTarget)}get show(){return this.DOM.show}get DOM(){return this._DOM}},ku=6,Au=1.02,ju=50,Q=()=>typeof window.CSSTransformValue<`u`,Mu=class{constructor(e,t=!1){this.dragState=0,this.minimumMoved=!1,this.pan={startX:0,endX:0,startY:0,overscrollX:0,overscrollY:0,letItGo:!1,preventClick:!1,translateX:0,translateY:0,touchID:0},this.pinch={startDistance:0,startScale:0,target:{X:0,Y:0},touchN:0,startTranslate:{X:0,Y:0}},this._scale=1,this.scaleDebouncer=0,this.frameBounds=null,this.debugger=null,this.btouchstartHandler=this.touchstartHandler.bind(this),this.btouchendHandler=this.touchendHandler.bind(this),this.btouchmoveHandler=this.touchmoveHandler.bind(this),this.bdblclickHandler=this.dblclickHandler.bind(this),this.bmousedownHandler=this.mousedownHandler.bind(this),this.bmouseupHandler=this.mouseupHandler.bind(this),this.bmousemoveHandler=this.mousemoveHandler.bind(this),this.moveFrame=0,this.dragTranslate=null,this.dragTransform=null,this.manager=e,this.coordinator=new Du,this.attachEvents(),t&&(this.debugger=new Ou)}get scale(){return this._scale}set scale(e){isNaN(e)&&(e=1),window.clearTimeout(this.scaleDebouncer),this.scaleDebouncer=window.setTimeout(()=>{this.dragState===0&&this.scale<Au&&(this.pan.translateX=0,this.pan.translateY=0,this.clearPan(),this.manager.updateBookStyle()),this.manager.listener(`zoom`,e)},100),this._scale=e}attachEvents(){this.observe(this.manager.spineElement),this.pan={startX:0,startY:0,endX:0,overscrollX:0,overscrollY:0,letItGo:!1,preventClick:!1,translateX:0,translateY:0,touchID:0},this.pinch={startDistance:0,startScale:0,target:{X:0,Y:0},startTranslate:{X:0,Y:0},touchN:0}}clearPan(){this.pan.letItGo=!1,this.pan.touchID=0,this.pan.endX=0,this.pan.overscrollX=0,this.pan.overscrollY=0}clearPinch(){this.pinch={startDistance:0,startScale:this.pinch.startScale,target:{X:0,Y:0},touchN:0,startTranslate:{X:0,Y:0}}}observe(e){e.addEventListener(`touchstart`,this.btouchstartHandler),e.addEventListener(`touchend`,this.btouchendHandler),e.addEventListener(`touchmove`,this.btouchmoveHandler,{passive:!0}),e.addEventListener(`dblclick`,this.bdblclickHandler,{passive:!0}),e.addEventListener(`mousedown`,this.bmousedownHandler),e.addEventListener(`mouseup`,this.bmouseupHandler),e.addEventListener(`mousemove`,this.bmousemoveHandler)}clickHandler(e){}touchstartHandler(e){if([`TEXTAREA`,`OPTION`,`INPUT`,`SELECT`].indexOf(e.target.nodeName)!==-1)return;switch(e.stopPropagation(),this.frameBounds=this.manager.currentBounds,this.coordinator.refreshOuterPixels(this.frameBounds),e.touches.length){case 3:return;case 2:{e.preventDefault(),this.pinch.startDistance=this.coordinator.getTouchDistance(e);let t=this.startTouch(e);this.pan.startX=t.X,this.pan.startY=t.Y,this.dragState=2,this.manager.updateBookStyle(!0),this.isScaled?(this.pinch.target.X-=this.pan.translateX*(this.pinch.startScale/this.scale),this.pinch.target.Y-=this.pan.translateY*(this.pinch.startScale/this.scale),this.pinch.target={X:0,Y:0},this.pinch.startScale=1/this.scale):(this.pinch.target={X:0,Y:0},this.pinch.startScale=this.scale),this.pinch.startTranslate={X:this.pan.translateX,Y:this.pan.translateY},this.debugger?.show&&(this.debugger.DOM.touch2.style.display=``,this.debugger.DOM.center.style.display=``,this.debugger.DOM.pinchTarget.style.display=``);return}case 1:this.pan.touchID=e.touches[0].identifier,this.debugger?.show&&(this.debugger.DOM.touch1.style.display=``);default:this.dragState<1&&(this.dragState=1),this.manager.updateBookStyle(!0)}this.manager.updateSpineStyle(!1);let t=this.startTouch(e);this.pan.startX=t.X,this.pan.startY=t.Y}startTouch(e){let t=this.coordinator.getTouchCenter(e)||this.coordinator.getBibiEventCoord(e);return{X:t.X-this.manager.width/2-this.pan.translateX*this.scale+this.manager.width/2,Y:t.Y-this.manager.height/2-this.pan.translateY*this.scale+this.manager.height/2}}touchendHandler(e){if(e.stopPropagation(),!e.touches||e.touches.length===0)this.pan.endX&&!this.isScaled?(this.pinch.touchN&&(this.pan.endX=this.pan.startX),this.updateAfterDrag()):!this.pinch.touchN&&Math.abs(this.pan.overscrollX)>ju&&Math.abs(this.pan.overscrollY)<ju/2&&(this.pan.startX=0,this.pan.endX=-this.pan.overscrollX,this.updateAfterDrag()),this.dragState=0,this.minimumMoved=!1,this.clearPinch(),this.debugger?.show&&(this.debugger.DOM.center.style.display=`none`,this.debugger.DOM.touch1.style.display=`none`,this.debugger.DOM.touch2.style.display=`none`);else if(e.touches.length===1){this.dragState=1,e.touches[0].identifier!==this.pan.touchID&&(this.pan.touchID=e.touches[0].identifier),this.debugger?.show&&(this.debugger.DOM.center.style.display=`none`,this.debugger.DOM.touch2.style.display=`none`,this.debugger.DOM.pinchTarget.style.display=`none`);let t=this.startTouch(e);this.pan.startX=t.X,this.pan.startY=t.Y}window.setTimeout(()=>{this.manager.updateBookStyle(!0),this.dragState===0&&(this.scale<Au&&(this.pan.translateX=0,this.pan.translateY=0),this.clearPan()),this.manager.updateBookStyle(!0)},50)}touchmoveHandler(e){e.stopPropagation();let t=this.coordinator.getBibiEventCoord(e);Math.abs(this.pan.startY-t.Y)+Math.abs(this.pan.startX-t.X)>5&&(this.minimumMoved||=(this.manager.deselect(),!0),this.dragState<1&&(this.dragState=1));let n=this.coordinator?.getTouchDistance(e),r=!1,i=this.scale;if(this.dragState===2&&n){if(this.pinch.touchN++,this.pinch.touchN<4)return;let e=n/this.pinch.startDistance*this.scale;e>=ku&&(e=ku),e<=Au&&(e=1),this.scale=e,this.pinch.startDistance=n,r=!0}if(this.pan.letItGo===!1&&(this.pan.letItGo=Math.abs(this.pan.startY-t.Y)<Math.abs(this.pan.startX-t.X)),this.debugger?.show&&(this.debugger.DOM.touch1.style.top=`${t.Y-10}px`,this.debugger.DOM.touch1.style.left=`${t.X-10}px`,this.debugger.DOM.touch1.innerText=`${t.X.toFixed(2)},${t.Y.toFixed(2)}`),this.dragState>0&&this.isScaled||this.dragState>1){if(this.dragState===1){let e={X:t.X-this.manager.width/2,Y:t.Y-this.manager.height/2};this.pan.translateX=(e.X-(this.pan.startX-this.manager.width/2))*1/this.scale,this.pan.translateY=(e.Y-(this.pan.startY-this.manager.height/2))*1/this.scale}else if(this.dragState===2){let t=this.coordinator.getTouchCenter(e);if(this.debugger?.show){this.debugger.DOM.center.style.top=`${t.Y-5}px`,this.debugger.DOM.center.style.left=`${t.X-5}px`,this.debugger.DOM.center.innerText=`${t.X.toFixed(2)},${t.Y.toFixed(2)}`;let n=this.coordinator.getBibiEventCoord(e,1);this.debugger.DOM.touch2.style.top=`${n.Y-10}px`,this.debugger.DOM.touch2.style.left=`${n.X-10}px`,this.debugger.DOM.touch2.innerText=`${n.X.toFixed(2)},${n.Y.toFixed(2)}`}t.X-=this.manager.width/2,t.Y-=this.manager.height/2;let n=-t.X/i;n+=t.X/this.scale,this.pinch.target.X+=n,t.X+=this.pinch.target.X*this.scale/this.pinch.startScale;let r=-t.Y/i;r+=t.Y/this.scale,this.pinch.target.Y+=r,t.Y+=this.pinch.target.Y*this.scale/this.pinch.startScale;let a=(t.X-(this.pan.startX-this.manager.width/2))*1/this.scale,o=(t.Y-(this.pan.startY-this.manager.height/2))*1/this.scale;this.pan.translateX=a,this.pan.translateY=o,this.debugger?.show&&(this.debugger.DOM.pinchTarget.style.left=`${this.pinch.target.X*this.scale/this.pinch.startScale-5+this.manager.width/2}px`,this.debugger.DOM.pinchTarget.style.top=`${this.pinch.target.Y*this.scale/this.pinch.startScale-5+this.manager.height/2}px`,this.debugger.DOM.pinchTarget.innerText=`${(this.pinch.target.X*this.scale/this.pinch.startScale).toFixed(2)},${(this.pinch.target.Y*this.scale/this.pinch.startScale).toFixed(2)}`)}let n=this.frameBounds.width/6,a=this.frameBounds.height/6;this.pan.translateX<-n&&(this.pan.overscrollX=-(n+this.pan.translateX),this.pan.translateX=-n),this.pan.translateY<-a&&(this.pan.overscrollY=-(a+this.pan.translateY),this.pan.translateY=-a),this.pan.translateX>n&&(this.pan.overscrollX=n-this.pan.translateX,this.pan.translateX=n),this.pan.translateY>a&&(this.pan.overscrollY=a-this.pan.translateY,this.pan.translateY=a),r=!0,this.debugger?.show&&(this.debugger.DOM.stats.innerText=`TX: ${this.pan.translateX.toFixed(2)}
TY: ${this.pan.translateY.toFixed(2)}
Zoom: ${this.scale.toFixed(2)}
Overscroll: ${this.pan.overscrollX.toFixed(2)},${this.pan.overscrollY.toFixed(2)}`)}if(r)this.manager.updateBookStyle();else if(this.dragState>0&&this.pan.letItGo){this.pan.endX=t.X;let e=this.manager.currentSlide*(this.manager.width/this.manager.perPage),n=this.pan.endX-this.pan.startX,r=this.manager.rtl?e+n:e-n,i=window.devicePixelRatio||1,a=Math.round((this.manager.rtl?1:-1)*r*i)/i;cancelAnimationFrame(this.moveFrame),this.moveFrame=requestAnimationFrame(()=>{requestAnimationFrame(()=>{Q()?(this.dragTransform||=(this.dragTranslate=new CSSTranslate(CSS.px(0),CSS.px(0),CSS.px(0)),new CSSTransformValue([this.dragTranslate])),this.dragTranslate.x.value=a,this.manager.spineElement.attributeStyleMap.set(`transform`,this.dragTransform)):this.manager.spineElement.style.transform=`translate3d(${a}px, 0, 0)`})})}}dblclickHandler(e){clearTimeout(this.dtimer),this.pdblclick=!0,this.dtimer=window.setTimeout(()=>this.pdblclick=!1,200),!this.disableDblClick&&this.isScaled&&(this.scale=1)}get isScaled(){return this.scale>1}addTouch(e){e.touches=[{pageX:e.pageX,pageY:e.pageY}]}mousedownHandler(e){this.isScaled&&(this.addTouch(e),this.touchstartHandler(e))}mouseupHandler(e){this.isScaled&&this.touchendHandler(e)}mousemoveHandler(e){this.isScaled&&e.buttons>0&&(e.preventDefault(),this.addTouch(e),this.touchmoveHandler(e))}updateAfterDrag(){let e=(this.manager.rtl?-1:1)*(this.pan.endX-this.pan.startX),t=Math.abs(e);e>0&&t>this.manager.threshold&&this.manager.slength>this.manager.perPage?this.manager.listener(`no_less`,void 0):e<0&&t>this.manager.threshold&&this.manager.slength>this.manager.perPage&&this.manager.listener(`no_more`,void 0),this.manager.slideToCurrent(!0,!0)}},Nu=class{constructor(e,t,n,r={},i=[],a=[]){this.frameIsAppended=!1,this.pendingUnwatchSelectors=[],this.currModules=[],this.viewportSize=void 0,this.serialize=Gc(),this.cachedPage=void 0,this.peripherals=e,this.debugHref=n,this.contentProtectionConfig={...r},this.keyboardPeripheralsConfig=[...i],this.resizeWatchSelectors=[...a],this.frame=document.createElement(`iframe`),this.frame.sandbox.value=`allow-same-origin allow-scripts`,this.frame.classList.add(`readium-navigator-iframe`),this.frame.classList.add(`blank`),this.frame.scrolling=`no`,this.frame.style.visibility=`hidden`,this.frame.ariaHidden=`true`,this.frame.style.display=`none`,this.frame.style.position=`absolute`,this.frame.style.pointerEvents=`none`,this.frame.style.transformOrigin=`0 0`,this.frame.style.transform=`scale(1)`,this.frame.style.background=`#fff`,this.frame.style.touchAction=`none`,this.frame.dataset.originalHref=n,this.source=`about:blank`,this.wrapper=document.createElement(`div`),this.wrapper.style.position=`relative`,this.wrapper.style.contain=`strict`,this.wrapper.style.float=this.wrapper.style.cssFloat=t===R.rtl?`right`:`left`}async load(e,t){return this.serialize(()=>this.loadNow(e,t))}async loadNow(e,t){return this.frameIsAppended||=(this.wrapper.appendChild(this.frame),!0),this.source===t&&this.loadPromise&&[...this.currModules].sort().join(`|`)===[...e].sort().join(`|`)||(this.loaded&&this.source!==t&&this.window.stop(),this.source=t,this.loadPromise=new Promise((t,n)=>{if(this.loader&&this.loaded){let n=this.frame.contentWindow;if([...this.currModules].sort().join(`|`)===[...e].sort().join(`|`)){try{t(n),this.loadPromise=void 0}catch{}return}this.comms?.halt(),this.loader.destroy(),this.loader=new Ec(n,e),this.currModules=e,this.comms=void 0;try{t(n),this.loadPromise=void 0}catch{}}else this.frame.addEventListener(`load`,()=>{let n=this.frame.contentWindow;this.loader=new Ec(n,e),this.currModules=e,this.peripherals.observe(this.wrapper),this.peripherals.observe(n);try{t(n)}catch{}},{once:!0}),this.frame.addEventListener(`error`,e=>{try{n(e.error),this.loadPromise=void 0}catch{}},{once:!0}),this.frame.style.removeProperty(`display`),this.frame.contentWindow.location.replace(this.source)})),this.loadPromise}loadPageSize(){if(this.viewportSize)return this.viewportSize;let e=this.frame.contentWindow,t=e.document.head.querySelector(`meta[name=viewport]`);if(t){let e=/(\w+) *= *([^\s,]+)/g,n,r=0,i=0;for(;n=e.exec(t.content);)n[1]===`width`?r=Number.parseFloat(n[2]):n[1]===`height`&&(i=Number.parseFloat(n[2]));if(r>0&&i>0)return this.viewportSize={width:r,height:i},this.viewportSize}return{width:e.document.body.scrollWidth,height:e.document.body.scrollHeight}}update(e){if(!this.loaded)return;let t=this.loadPageSize(),n=Math.min(this.wrapper.clientWidth/t.width,this.wrapper.clientHeight/t.height);Q()?(this.frame.attributeStyleMap.set(`width`,CSS.px(t.width)),this.frame.attributeStyleMap.set(`height`,CSS.px(t.height)),this.frame.attributeStyleMap.set(`transform`,new CSSTransformValue([new CSSScale(n,n)]))):(this.frame.style.height=`${t.height}px`,this.frame.style.width=`${t.width}px`,this.frame.style.transform=`scale(${n})`);let r=this.frame.getBoundingClientRect(),i=this.wrapper.clientHeight-r.height;if(Q()){if(this.frame.attributeStyleMap.set(`top`,CSS.px(i/2)),e===O.left){let e=this.wrapper.clientWidth-r.width;this.frame.attributeStyleMap.set(`left`,CSS.px(e))}else if(e===O.center){let e=this.wrapper.clientWidth-r.width;this.frame.attributeStyleMap.set(`left`,CSS.px(e/2))}else this.frame.attributeStyleMap.set(`left`,CSS.px(0))}else if(this.frame.style.top=`${i/2}px`,e===O.left){let e=this.wrapper.clientWidth-r.width;this.frame.style.left=`${e}px`}else if(e===O.center){let e=this.wrapper.clientWidth-r.width;this.frame.style.left=`${e/2}px`}else this.frame.style.left=`0px`;this.frame.style.removeProperty(`visibility`),this.frame.ariaHidden=null,this.frame.style.removeProperty(`pointer-events`),this.frame.classList.remove(`blank`),this.frame.classList.add(`loaded`)}async destroy(){return this.serialize(async()=>{this.conditionBridge?.destroy(),await this.unfocusNow(),this.loader?.destroy(),this.wrapper.remove()})}async unload(){return this.serialize(()=>this.unloadNow())}async unloadNow(){if(this.loaded)return this.deselect(),this.frame.style.visibility=`hidden`,this.frame.ariaHidden=`true`,this.frame.style.pointerEvents=`none`,this.frame.classList.add(`blank`),this.frame.classList.remove(`loaded`),this.comms?.halt(),this.loader?.destroy(),this.comms=void 0,this.frame.blur(),new Promise((e,t)=>{this.frame.addEventListener(`load`,()=>{try{this.showPromise=void 0,e()}catch{}},{once:!0}),this.frame.addEventListener(`error`,e=>{try{this.showPromise=void 0,t(e.error)}catch{}},{once:!0}),this.source=`about:blank`,this.frame.contentWindow.location.replace(`about:blank`),this.frame.style.display=`none`,this.frame.style.width=`0px`,this.frame.style.height=`0px`})}deselect(){this.frame.contentWindow?.getSelection()?.removeAllRanges()}async unfocus(){return this.serialize(()=>this.unfocusNow())}async unfocusNow(){if(this.frame.parentElement)return this.comms===void 0||!this.comms.ready?void 0:(this.frame.blur(),new Promise((e,t)=>{this.comms?.send(`unfocus`,void 0,t=>{this.comms?.halt(),this.showPromise=void 0,e()})}));this.comms?.halt()}applyContentProtection(){this.comms||this.comms.resume(),this.comms.send(`peripherals_protection`,this.contentProtectionConfig),this.keyboardPeripheralsConfig&&this.keyboardPeripheralsConfig.length>0&&(this.conditionBridge?.destroy(),this.conditionBridge=new Wc(this.keyboardPeripheralsConfig,e=>{e.length>0&&this.comms.send(`keyboard_peripherals`,e)}),this.conditionBridge.setup()),this.contentProtectionConfig.protectPrinting?.disable&&this.comms.send(`print_protection`,this.contentProtectionConfig.protectPrinting),this.resizeWatchSelectors.forEach(e=>{this.comms.send(`decoration_resize`,{action:`watch`,selector:e})}),this.pendingUnwatchSelectors.forEach(e=>{this.comms.send(`decoration_resize`,{action:`unwatch`,selector:e})}),this.pendingUnwatchSelectors=[]}addResizeTarget(e){this.resizeWatchSelectors.includes(e)||this.resizeWatchSelectors.push(e),this.pendingUnwatchSelectors=this.pendingUnwatchSelectors.filter(t=>t!==e),this.comms?.ready&&this.comms.send(`decoration_resize`,{action:`watch`,selector:e})}removeResizeTarget(e){this.resizeWatchSelectors=this.resizeWatchSelectors.filter(t=>t!==e),this.comms?.ready?this.comms.send(`decoration_resize`,{action:`unwatch`,selector:e}):this.pendingUnwatchSelectors.includes(e)||this.pendingUnwatchSelectors.push(e)}async show(e){return this.serialize(()=>this.showNow(e))}async showNow(e){if(!this.frame.parentElement)console.warn(`Trying to show frame that is not attached to the DOM`);else if(!this.loaded)this.showPromise=void 0;else return this.showPromise?(this.cachedPage!==e&&(this.update(e),this.cachedPage=e),this.showPromise):(this.cachedPage=e,this.comms?this.comms.resume():this.comms=new Uc(this.frame.contentWindow,this.source),this.showPromise=new Promise((e,t)=>{this.comms.send(`focus`,void 0,t=>{this.update(this.cachedPage),this.applyContentProtection(),e()})}),this.showPromise)}async activate(){return this.serialize(()=>new Promise((e,t)=>{if(!this.comms?.ready)return e();this.comms?.send(`activate`,void 0,()=>{e()})}))}get element(){return this.wrapper}get iframe(){return this.frame}get realSize(){return this.frame.getBoundingClientRect()}get loaded(){return this.frame.contentWindow&&this.frame.contentWindow.location.href!==`about:blank`}set width(e){if(Q()){let t=this.wrapper.attributeStyleMap.get(`width`);if(t instanceof CSSUnitValue&&t.unit===`percent`&&t.value===e)return;this.wrapper.attributeStyleMap.set(`width`,CSS.percent(e))}else{let t=`${e}%`;if(this.wrapper.style.width===t)return;this.wrapper.style.width=t}}set height(e){if(Q()){let t=this.wrapper.attributeStyleMap.get(`height`);if(t instanceof CSSUnitValue&&t.unit===`px`&&t.value===e)return;this.wrapper.attributeStyleMap.set(`height`,CSS.px(e))}else{let t=`${e}px`;if(this.wrapper.style.height===t)return;this.wrapper.style.height=t}}get window(){if(!this.frame.contentWindow)throw Error(`Trying to use frame window when it doesn't exist`);return this.frame.contentWindow}get atLeft(){return this.window.scrollX<5}get atRight(){return this.window.scrollX>this.window.document.scrollingElement.scrollWidth-this.window.innerWidth-5}get msg(){return this.comms}get ldr(){return this.loader}},Pu=(e=>(e.auto=`auto`,e.landscape=`landscape`,e.portrait=`portrait`,e))(Pu||{}),Fu=(e=>(e.auto=`auto`,e.both=`both`,e.none=`none`,e.landscape=`landscape`,e))(Fu||{}),Iu=class{constructor(e){this.shift=!0,this.spreads=[],this.nLandscape=0,this.index(e),this.testShift(e),console.log(`Indexed ${this.spreads.length} spreads for ${e.readingOrder.items.length} items`)}index(e,t=!1){this.nLandscape=0,e.readingOrder.items.forEach((n,r)=>{t||(e.readingOrder.items[r]=n.addProperties({number:r+1,isImage:n.type?.indexOf(`image/`)===0}));let i=n.properties?.otherProperties.orientation===`landscape`;(!n.properties?.page||t)&&(n.properties=n.properties?.add({page:i?`center`:(+!this.shift+r-this.nLandscape)%2?e.metadata.readingProgression===R.rtl?`right`:`left`:e.metadata.readingProgression===R.rtl?`left`:`right`})),(i||n.properties?.otherProperties.addBlank)&&this.nLandscape++}),t&&(this.spreads=[]),this.buildSpreads(e.readingOrder)}testShift(e){let t=!1;this.spreads.forEach((e,n)=>{if(e.length>1)return;let r=e[0],i=r.properties?.otherProperties.orientation;n===0&&(i===`landscape`||i!==`portrait`&&((r.width||0)>(r.height||0)||r.properties?.otherProperties.spread===`both`))&&(this.shift=!1),t&&r.properties?.page===O.center&&this.spreads[n-1][0].addProperties({addBlank:!0}),t=i===`portrait`&&r.properties?.page!==`center`&&r.properties?.otherProperties.number>1}),this.shift||this.index(e,!0)}buildSpreads(e){let t=[];e.items.forEach((e,n)=>{!n&&this.shift?this.spreads.push([e]):e.properties?.page===O.center?(t.length>0&&this.spreads.push(t),this.spreads.push([e]),t=[]):t.length>=2?(this.spreads.push(t),t=[e]):t.push(e)}),t.length>0&&this.spreads.push(t)}currentSpread(e,t){return this.spreads[Math.min(Math.floor(e/t),this.spreads.length-1)]}findByLink(e){return this.spreads.find(t=>t.includes(e))||void 0}},Lu=8,Ru=5,zu=300,Bu=15e3,Vu=250,Hu=150,Uu=500,Wu=class{constructor(e,t,n,r,i,a,o,s=[],c){if(this.pool=new Map,this.blobs=new Map,this.inprogress=new Map,this.delayedShow=new Map,this.delayedTimeout=new Map,this.previousFrames=[],this.injector=null,this.width=0,this.height=0,this.currentSlide=0,this.spread=!0,this.orientationInternal=-1,this.bookScale=null,this.bookTranslate=null,this.bookTransform=null,this.container=e,this.positions=t,this.pub=n,this.injector=i??null,this.contentProtectionConfig=a||{},this.keyboardPeripheralsConfig=o||[],this.resizeWatchSelectors=[...s],this.upgradeInsecureRequests=c??`always`,this.spreadPresentation=n.metadata.otherMetadata?.spread||Fu.auto,this.pub.metadata.effectiveReadingProgression!==R.rtl&&this.pub.metadata.effectiveReadingProgression!==R.ltr)throw Error(`Unsupported reading progression for fixed-layout EPUB`);this.spreader=new Iu(this.pub),this.containerHeightCached=e.clientHeight,this.bookElement=document.createElement(`div`),this.bookElement.ariaLabel=`Book`,this.bookElement.tabIndex=-1,this.updateBookStyle(!0),this.spineElement=document.createElement(`div`),this.spineElement.ariaLabel=`Spine`,this.bookElement.appendChild(this.spineElement),this.container.appendChild(this.bookElement),this.updateSpineStyle(!0),this.peripherals=new Mu(this);let l=document.createDocumentFragment();this.pub.readingOrder.items.forEach(e=>{let t=new Nu(this.peripherals,this.pub.metadata.effectiveReadingProgression,e.href,this.contentProtectionConfig,this.keyboardPeripheralsConfig,this.resizeWatchSelectors);this.pool.set(e.href,t),t.width=100/this.length*(e.properties?.otherProperties.orientation===Pu.landscape||e.properties?.otherProperties.addBlank?this.perPage:1),t.height=this.height,l.appendChild(t.wrapper)}),this.spineElement.appendChild(l)}set listener(e){this._listener=e}get listener(){return this._listener}get doNotDisturb(){return this.peripherals.pan.touchID>0}resizeHandler(e=!0,t=!0){this.currentSlide+this.perPage>this.length&&(this.currentSlide=this.length<=this.perPage?0:this.length-1),this.containerHeightCached=this.container.clientHeight,this.orientationInternal=-1,this.updateSpineStyle(!0),e&&(this.currentSlide=this.reAlign(),this.slideToCurrent(!t,t)),clearTimeout(this.resizeTimeout),this.resizeTimeout=window.setTimeout(()=>{let e=100/this.length,t=new Map(this.pub.readingOrder.items.map(e=>[e.href,e]));this.pool.forEach((n,r)=>{let i=t.get(r);i&&requestAnimationFrame(()=>{if(n.width=e*(i.properties?.otherProperties.orientation===Pu.landscape||i.properties?.otherProperties.addBlank?this.perPage:1),n.height=this.height,!n.loaded)return;let t=this.spreader.findByLink(i);n.update(this.spreadPosition(t,i))})})},Vu)}updateDimensions(){this.width=this.bookElement.clientWidth,this.height=this.bookElement.clientHeight}get rtl(){return this.pub.metadata.effectiveReadingProgression===R.rtl}get single(){return!this.spread||this.portrait}get perPage(){return this.spread&&!this.portrait?2:1}get threshold(){return 50}get portrait(){return this.spreadPresentation===Fu.none||(this.orientationInternal===-1&&(this.orientationInternal=+(this.containerHeightCached>this.container.clientWidth)),this.orientationInternal===1)}updateSpineStyle(e,t=!0){let n=0;if(this.updateDimensions(),this.perPage>1&&(n=this.width/2),Q())this.spineElement.attributeStyleMap.set(`transition`,new CSSUnparsedValue([e?`all ${t?Hu:Uu}ms ease-out`:`all 0ms ease-out`])),this.spineElement.attributeStyleMap.set(`margin-right`,CSS.px(this.rtl?n:0)),this.spineElement.attributeStyleMap.set(`margin-left`,CSS.px(this.rtl?0:n)),this.spineElement.attributeStyleMap.set(`width`,CSS.px(this.width/this.perPage*this.length)),this.transform?this.spineElement.attributeStyleMap.set(`transform`,new CSSTransformValue([new CSSTranslate(CSS.px(this.transform||0),CSS.px(0),CSS.px(0))])):this.spineElement.attributeStyleMap.delete(`transform`),this.spineElement.attributeStyleMap.set(`contain`,new CSSUnparsedValue([`content`]));else{let r={transition:e?`all ${t?Hu:Uu}ms ease-out`:`all 0ms ease-out`,marginRight:this.rtl?`${n}px`:`0`,marginLeft:this.rtl?`0`:`${n}px`,width:`${this.width/this.perPage*this.length}px`,transform:this.transform?`translate3d(${this.transform}px, 0px, 0px)`:``,contain:`content`};Object.assign(this.spineElement.style,r)}}updateBookStyle(e=!1){if(e){let e={overflow:`hidden`,direction:this.pub.metadata.effectiveReadingProgression,cursor:``,height:`100%`,width:`100%`,position:`relative`,outline:`none`,transition:this.peripherals?.dragState?`none`:`transform .15s ease-in-out`,touchAction:`none`};Object.assign(this.bookElement.style,e)}let t=this.peripherals?.scale||1,n=this.peripherals?.pan.translateX||0,r=this.peripherals?.pan.translateY||0;Q()?(this.bookTransform||=(this.bookScale=new CSSScale(1,1),this.bookTranslate=new CSSTranslate(CSS.px(0),CSS.px(0),CSS.px(0)),new CSSTransformValue([this.bookScale,this.bookTranslate])),this.bookScale.x.value=t,this.bookScale.y.value=t,this.bookTranslate.x.value=n,this.bookTranslate.y.value=r,this.bookElement.attributeStyleMap.set(`transform`,this.bookTransform)):this.bookElement.style.transform=`scale(${t}) translate3d(${n}px, ${r}px, 0px)`}goTo(e){if(this.slength<=this.perPage)return;e=this.reAlign(e);let t=this.currentSlide;this.currentSlide=Math.min(Math.max(e,0),this.length-1),t!==this.currentSlide&&this.slideToCurrent(!1)}onChange(){this.peripherals.scale=1,this.updateBookStyle()}get offset(){return(this.rtl?1:-1)*this.currentSlide*(this.width/this.perPage)}get length(){if(this.single)return this.slength;let e=this.slength+this.nLandscape;return this.shift&&e%2==0?e+1:e}get slength(){return this.pub.readingOrder.items.length||0}get shift(){return this.spreader.shift}get nLandscape(){return this.spreader.nLandscape}setPerPage(e){this.spread=e===null||e!==1,requestAnimationFrame(()=>this.resizeHandler(!0))}slideToCurrent(e,t=!0){this.updateDimensions(),e?requestAnimationFrame(()=>{requestAnimationFrame(()=>{this.transform=this.offset,this.updateSpineStyle(!0,t),this.deselect()})}):(this.transform=this.offset,this.updateSpineStyle(!1),this.deselect())}bounce(e=!1){requestAnimationFrame(()=>{this.transform=this.offset+50*(e?1:-1),this.updateSpineStyle(!0,!0),setTimeout(()=>{this.transform=this.offset,this.updateSpineStyle(!0,!0)},100)})}next(e=1){if(this.slength<=this.perPage)return!1;let t=this.currentSlide;return this.currentSlide=Math.min(this.currentSlide+e,this.length-1),this.perPage>1&&this.currentSlide%2&&this.currentSlide--,this.currentSlide===t&&(this.currentSlide+1,this.length),t===this.currentSlide?(this.bounce(this.rtl),!1):(this.slideToCurrent(!0),this.onChange(),!0)}prev(e=1){if(this.slength<=this.perPage)return!1;let t=this.currentSlide;return this.currentSlide=Math.max(this.currentSlide-e,0),this.perPage>1&&this.currentSlide%2&&this.currentSlide++,t===this.currentSlide?(this.bounce(!this.rtl),!1):(this.slideToCurrent(!0),this.onChange(),!0)}get ownerWindow(){return this.container.ownerDocument.defaultView||window}async destroy(){let e=this.inprogress.values(),t=e.next(),n=[];for(;t.value;)n.push(t.value),t=e.next();n.length>0&&await Promise.allSettled(n),this.inprogress.clear();let r=this.pool.values(),i=r.next();for(;i.value;)await i.value.destroy(),i=r.next();this.pool.clear(),this.blobs.forEach(e=>e.reset()),this.blobs.clear(),this.injector?.dispose(),this.container.childNodes.forEach(e=>{(e.nodeType===Node.ELEMENT_NODE||e.nodeType===Node.TEXT_NODE)&&e.remove()})}makeSpread(e){return this.perPage<2?[this.pub.readingOrder.items[e]]:this.spreader.currentSpread(e,this.perPage)}reAlign(e=this.currentSlide){return e%2&&!this.single&&e++,e}spreadPosition(e,t){return this.perPage<2||e.length<2?O.center:t.href===e[0].href?this.rtl?O.right:O.left:this.rtl?O.left:O.right}async waitForItem(e){if(this.inprogress.has(e)&&await this.inprogress.get(e),this.delayedShow.has(e)){let t=this.delayedTimeout.get(e);t>0?clearTimeout(t):await this.delayedShow.get(e),this.delayedTimeout.set(e,0),this.delayedShow.delete(e)}}async cancelShowing(e){if(this.delayedShow.has(e)){let t=this.delayedTimeout.get(e);t>0&&clearTimeout(t),this.delayedShow.delete(e)}}async update(e,t,n,r=!1){let i=this.pub.readingOrder.items.findIndex(e=>e.href===t.href);if(i<0)throw Error(`Href not found in reading order`);this.currentSlide!==i&&(this.currentSlide=this.reAlign(i),this.slideToCurrent(!0));let a=this.makeSpread(this.currentSlide);this.perPage>1&&i++;for(let e of a)await this.waitForItem(e.href);let o=new Promise(async(t,r)=>{let o=[],s=[];this.positions.forEach((e,t)=>{(t>i+Lu||t<i-Lu)&&(o.includes(e.href)||o.push(e.href)),t<i+Ru&&t>i-Ru&&(s.includes(e.href)||s.push(e.href))}),o.forEach(async e=>{s.includes(e)||this.pool.has(e)&&(this.cancelShowing(e),await this.pool.get(e)?.unload(),this.blobs.get(e)?.reset())}),this.currentBaseURL!==void 0&&e.baseURL!==this.currentBaseURL&&(this.blobs.forEach(e=>e.reset()),this.blobs.clear()),this.currentBaseURL=e.baseURL;let c=async t=>{let r=e.readingOrder.findIndexWithHref(t),i=e.readingOrder.items[r];i&&(this.blobs.has(t)||this.blobs.set(t,new bu(e,this.currentBaseURL||``,i,{injector:this.injector,upgradeInsecureRequests:this.upgradeInsecureRequests})),this.delayedShow.has(t)||this.delayedShow.set(t,new Promise((e,a)=>{let o=!1,s=window.setTimeout(async()=>{this.delayedTimeout.set(t,0);let a=this.makeSpread(this.reAlign(r)),s=this.spreadPosition(a,i),c=this.pool.get(t);await c.load(n,await this.blobs.get(t).build(!0)),this.peripherals.isScaled||await c.show(s),this.delayedShow.delete(t),o=!0,e()},zu);setTimeout(()=>{!o&&this.delayedShow.has(t)&&a(`Offscreen load timeout: ${t}`)},Bu),this.delayedTimeout.set(t,s)})))};try{await Promise.all(s.map(e=>c(e)))}catch(e){r(e)}let l=[];for(let e of a){let t=this.pool.get(e.href),r=this.blobs.get(e.href);r&&(this.cancelShowing(e.href),await t.load(n,await r.build(!0)),await t.show(this.spreadPosition(a,e)),this.previousFrames.push(t),await t.activate(),l.push(t))}for(;this.previousFrames.length>0;){let e=this.previousFrames.shift();e&&!l.includes(e)&&await e.unfocus()}this.previousFrames=l;let u=this.container.ownerDocument.activeElement;u&&u.tagName===`IFRAME`&&!l.some(e=>e.iframe===u)&&l[0]?.iframe.focus({preventScroll:!0}),t()});for(let e of a)this.inprogress.set(e.href,o);try{await o}finally{for(let e of a)this.inprogress.delete(e.href)}}addResizeTarget(e){this.resizeWatchSelectors.includes(e)||this.resizeWatchSelectors.push(e),this.pool.forEach(t=>t.addResizeTarget(e))}removeResizeTarget(e){this.resizeWatchSelectors=this.resizeWatchSelectors.filter(t=>t!==e),this.pool.forEach(t=>t.removeResizeTarget(e))}get currentFrames(){if(this.perPage<2){let e=this.pub.readingOrder.items[this.currentSlide];return[this.pool.get(e.href)]}return this.spreader.currentSpread(this.currentSlide,this.perPage).map(e=>this.pool.get(e.href))}get currentBounds(){let e={x:0,y:0,width:0,height:0,top:0,right:0,bottom:0,left:0,toJSON(){return this}};return this.currentFrames.forEach(t=>{if(!t)return;let n=t.realSize;e.x=Math.min(e.x,n.x),e.y=Math.min(e.y,n.y),e.width+=n.width,e.height=Math.max(e.height,n.height),e.top=Math.min(e.top,n.top),e.right=Math.min(e.right,n.right),e.bottom=Math.min(e.bottom,n.bottom),e.left=Math.min(e.left,n.left)}),e}get viewport(){let e={readingOrder:[],progressions:new Map,positions:null};return(this.perPage<2?[this.pub.readingOrder.items[this.currentSlide]]:this.spreader.currentSpread(this.currentSlide,this.perPage)).forEach(t=>{e.readingOrder.push(t.href),e.progressions.set(t.href,{start:0,end:1})}),e.positions=this.getCurrentNumbers(),e}getCurrentNumbers(){if(this.perPage<2)return[this.pub.readingOrder.items[this.currentSlide].properties?.otherProperties.number];let e=this.spreader.currentSpread(this.currentSlide,this.perPage);return e.length>1?[e[0].properties?.otherProperties.number,e[e.length-1].properties?.otherProperties.number]:[e[0].properties?.otherProperties.number]}deselect(){this.currentFrames?.forEach(e=>e?.deselect())}},Gu=class e{constructor(e={}){this.backgroundColor=G(e.backgroundColor),this.blendFilter=K(e.blendFilter),this.constraint=q(e.constraint),this.columnCount=q(e.columnCount),this.darkenFilter=Dl(e.darkenFilter),this.deprecatedFontSize=K(e.deprecatedFontSize),this.fontFamily=G(e.fontFamily),this.fontSize=J(e.fontSize,sl.range),this.fontSizeNormalize=K(e.fontSizeNormalize),this.fontOpticalSizing=K(e.fontOpticalSizing),this.fontWeight=J(e.fontWeight,cl.range),this.fontWidth=J(e.fontWidth,ll.range),this.hyphens=K(e.hyphens),this.invertFilter=Dl(e.invertFilter),this.invertGaijiFilter=Dl(e.invertGaijiFilter),this.iOSPatch=K(e.iOSPatch),this.iPadOSPatch=K(e.iPadOSPatch),this.letterSpacing=q(e.letterSpacing),this.ligatures=K(e.ligatures),this.lineHeight=q(e.lineHeight),this.linkColor=G(e.linkColor),this.noRuby=K(e.noRuby),this.pageGutter=q(e.pageGutter),this.paragraphIndent=q(e.paragraphIndent),this.paragraphSpacing=q(e.paragraphSpacing),this.scroll=K(e.scroll),this.scrollPaddingTop=q(e.scrollPaddingTop),this.scrollPaddingBottom=q(e.scrollPaddingBottom),this.scrollPaddingLeft=q(e.scrollPaddingLeft),this.scrollPaddingRight=q(e.scrollPaddingRight),this.selectionBackgroundColor=G(e.selectionBackgroundColor),this.selectionTextColor=G(e.selectionTextColor),this.textAlign=El(e.textAlign,al),this.textColor=G(e.textColor),this.textNormalization=K(e.textNormalization),this.visitedColor=G(e.visitedColor),this.wordSpacing=q(e.wordSpacing),this.optimalLineLength=q(e.optimalLineLength),this.maximalLineLength=q(e.maximalLineLength),this.minimalLineLength=q(e.minimalLineLength)}static serialize(e){let{...t}=e;return JSON.stringify(t)}static deserialize(t){try{let n=JSON.parse(t);return new e(n)}catch(e){return console.error(`Failed to deserialize preferences:`,e),null}}merging(t){let n={...this};for(let e of Object.keys(t))t[e]!==void 0&&(e!==`maximalLineLength`||t[e]===null||t[e]>=(t.optimalLineLength??n.optimalLineLength??65))&&(e!==`minimalLineLength`||t[e]===null||t[e]<=(t.optimalLineLength??n.optimalLineLength??65))&&(n[e]=t[e]);return new e(n)}},Ku=class{constructor(e){this.backgroundColor=G(e.backgroundColor)||null,this.blendFilter=K(e.blendFilter)??!1,this.constraint=q(e.constraint)||0,this.columnCount=q(e.columnCount)||null,this.darkenFilter=Dl(e.darkenFilter)??!1,this.deprecatedFontSize=K(e.deprecatedFontSize),(this.deprecatedFontSize===!1||this.deprecatedFontSize===null)&&(this.deprecatedFontSize=!CSS.supports(`zoom`,`1`)),this.fontFamily=G(e.fontFamily)||null,this.fontSize=J(e.fontSize,sl.range)||1,this.fontSizeNormalize=K(e.fontSizeNormalize)??!1,this.fontOpticalSizing=K(e.fontOpticalSizing)??null,this.fontWeight=J(e.fontWeight,cl.range)||null,this.fontWidth=J(e.fontWidth,ll.range)||null,this.hyphens=K(e.hyphens)??null,this.invertFilter=Dl(e.invertFilter)??!1,this.invertGaijiFilter=Dl(e.invertGaijiFilter)??!1,this.iOSPatch=e.iOSPatch!==!1&&(V.OS.iOS||V.OS.iPadOS)&&V.iOSRequest===`mobile`,this.iPadOSPatch=e.iPadOSPatch!==!1&&V.OS.iPadOS&&V.iOSRequest===`desktop`,this.letterSpacing=q(e.letterSpacing)||null,this.ligatures=K(e.ligatures)??null,this.lineHeight=q(e.lineHeight)||null,this.linkColor=G(e.linkColor)||null,this.noRuby=K(e.noRuby)??!1,this.pageGutter=Ol(q(e.pageGutter),20),this.paragraphIndent=q(e.paragraphIndent)??null,this.paragraphSpacing=q(e.paragraphSpacing)??null,this.scroll=K(e.scroll)??!1,this.scrollPaddingTop=q(e.scrollPaddingTop)??null,this.scrollPaddingBottom=q(e.scrollPaddingBottom)??null,this.scrollPaddingLeft=q(e.scrollPaddingLeft)??null,this.scrollPaddingRight=q(e.scrollPaddingRight)??null,this.selectionBackgroundColor=G(e.selectionBackgroundColor)||null,this.selectionTextColor=G(e.selectionTextColor)||null,this.textAlign=El(e.textAlign,al)||null,this.textColor=G(e.textColor)||null,this.textNormalization=K(e.textNormalization)??!1,this.visitedColor=G(e.visitedColor)||null,this.wordSpacing=q(e.wordSpacing)||null,this.optimalLineLength=q(e.optimalLineLength)||65,this.maximalLineLength=Ol(Tl(e.maximalLineLength,this.optimalLineLength),80),this.minimalLineLength=Ol(wl(e.minimalLineLength,this.optimalLineLength),40),this.experiments=kl(e.experiments)||null}},qu={backgroundColor:`#FFFFFF`,textColor:`#121212`,linkColor:`#0000EE`,visitedColor:`#551A8B`,selectionBackgroundColor:`#b4d8fe`,selectionTextColor:`inherit`},Ju=class{constructor(e,t,n){this.preferences=new Gu({...e}),this.settings=t,this.metadata=n,this.layout=this.metadata?.effectiveLayout||D.reflowable}clear(){this.preferences=new Gu({backgroundColor:null,blendFilter:null,columnCount:null,constraint:null,darkenFilter:null,deprecatedFontSize:null,fontFamily:null,fontSize:null,fontSizeNormalize:null,fontOpticalSizing:null,fontWeight:null,fontWidth:null,hyphens:null,invertFilter:null,invertGaijiFilter:null,iOSPatch:null,iPadOSPatch:null,letterSpacing:null,ligatures:null,lineHeight:null,linkColor:null,maximalLineLength:null,minimalLineLength:null,noRuby:null,optimalLineLength:null,pageGutter:null,paragraphIndent:null,paragraphSpacing:null,scroll:null,scrollPaddingTop:null,scrollPaddingBottom:null,scrollPaddingLeft:null,scrollPaddingRight:null,selectionBackgroundColor:null,selectionTextColor:null,textAlign:null,textColor:null,textNormalization:null,visitedColor:null,wordSpacing:null})}updatePreference(e,t){this.preferences[e]=t}get backgroundColor(){return new Y({initialValue:this.preferences.backgroundColor,effectiveValue:this.settings.backgroundColor||qu.backgroundColor,isEffective:this.preferences.backgroundColor!==null,onChange:e=>{this.updatePreference(`backgroundColor`,e??null)}})}get blendFilter(){return new X({initialValue:this.preferences.blendFilter,effectiveValue:this.settings.blendFilter||!1,isEffective:this.preferences.blendFilter!==null,onChange:e=>{this.updatePreference(`blendFilter`,e??null)}})}get columnCount(){return new Y({initialValue:this.preferences.columnCount,effectiveValue:this.settings.columnCount||null,isEffective:this.layout!==D.fixed&&!this.settings.scroll,onChange:e=>{this.updatePreference(`columnCount`,e??null)}})}get constraint(){return new Y({initialValue:this.preferences.constraint,effectiveValue:this.preferences.constraint||0,isEffective:!0,onChange:e=>{this.updatePreference(`constraint`,e??null)}})}get darkenFilter(){return new Z({initialValue:typeof this.preferences.darkenFilter==`boolean`?100:this.preferences.darkenFilter,effectiveValue:typeof this.settings.darkenFilter==`boolean`?100:this.settings.darkenFilter||0,isEffective:this.settings.darkenFilter!==null,onChange:e=>{this.updatePreference(`darkenFilter`,e??null)},supportedRange:ol.range,step:ol.step})}get deprecatedFontSize(){return new X({initialValue:this.preferences.deprecatedFontSize,effectiveValue:!CSS.supports(`zoom`,`1`)||this.settings.deprecatedFontSize||!1,isEffective:this.layout!==D.fixed,onChange:e=>{this.updatePreference(`deprecatedFontSize`,e??null)}})}get fontFamily(){return new Y({initialValue:this.preferences.fontFamily,effectiveValue:this.settings.fontFamily||null,isEffective:this.layout!==D.fixed,onChange:e=>{this.updatePreference(`fontFamily`,e??null)}})}get fontSize(){return new Z({initialValue:this.preferences.fontSize,effectiveValue:this.settings.fontSize||1,isEffective:this.layout!==D.fixed,onChange:e=>{this.updatePreference(`fontSize`,e??null)},supportedRange:sl.range,step:sl.step})}get fontSizeNormalize(){return new X({initialValue:this.preferences.fontSizeNormalize,effectiveValue:this.settings.fontSizeNormalize||!1,isEffective:this.layout!==D.fixed&&this.preferences.fontSizeNormalize!==null,onChange:e=>{this.updatePreference(`fontSizeNormalize`,e??null)}})}get fontOpticalSizing(){return new X({initialValue:this.preferences.fontOpticalSizing,effectiveValue:this.settings.fontOpticalSizing||!0,isEffective:this.layout!==D.fixed&&this.preferences.fontOpticalSizing!==null,onChange:e=>{this.updatePreference(`fontOpticalSizing`,e??null)}})}get fontWeight(){return new Z({initialValue:this.preferences.fontWeight,effectiveValue:this.settings.fontWeight||400,isEffective:this.layout!==D.fixed&&this.preferences.fontWeight!==null,onChange:e=>{this.updatePreference(`fontWeight`,e??null)},supportedRange:cl.range,step:cl.step})}get fontWidth(){return new Z({initialValue:this.preferences.fontWidth,effectiveValue:this.settings.fontWidth||100,isEffective:this.layout!==D.fixed&&this.preferences.fontWidth!==null,onChange:e=>{this.updatePreference(`fontWidth`,e??null)},supportedRange:ll.range,step:ll.step})}get hyphens(){return new X({initialValue:this.preferences.hyphens,effectiveValue:this.settings.hyphens||!1,isEffective:this.layout!==D.fixed&&this.metadata?.effectiveReadingProgression===R.ltr&&this.preferences.hyphens!==null,onChange:e=>{this.updatePreference(`hyphens`,e??null)}})}get invertFilter(){return new Z({initialValue:typeof this.preferences.invertFilter==`boolean`?100:this.preferences.invertFilter,effectiveValue:typeof this.settings.invertFilter==`boolean`?100:this.settings.invertFilter||0,isEffective:this.settings.invertFilter!==null,onChange:e=>{this.updatePreference(`invertFilter`,e??null)},supportedRange:ol.range,step:ol.step})}get invertGaijiFilter(){return new Z({initialValue:typeof this.preferences.invertGaijiFilter==`boolean`?100:this.preferences.invertGaijiFilter,effectiveValue:typeof this.settings.invertGaijiFilter==`boolean`?100:this.settings.invertGaijiFilter||0,isEffective:this.preferences.invertGaijiFilter!==null,onChange:e=>{this.updatePreference(`invertGaijiFilter`,e??null)},supportedRange:ol.range,step:ol.step})}get iOSPatch(){return new X({initialValue:this.preferences.iOSPatch,effectiveValue:this.settings.iOSPatch||!1,isEffective:this.layout!==D.fixed,onChange:e=>{this.updatePreference(`iOSPatch`,e??null)}})}get iPadOSPatch(){return new X({initialValue:this.preferences.iPadOSPatch,effectiveValue:this.settings.iPadOSPatch||!1,isEffective:this.layout!==D.fixed,onChange:e=>{this.updatePreference(`iPadOSPatch`,e??null)}})}get letterSpacing(){return new Z({initialValue:this.preferences.letterSpacing,effectiveValue:this.settings.letterSpacing||0,isEffective:this.layout!==D.fixed&&this.preferences.letterSpacing!==null,onChange:e=>{this.updatePreference(`letterSpacing`,e??null)},supportedRange:ul.range,step:ul.step})}get ligatures(){return new X({initialValue:this.preferences.ligatures,effectiveValue:this.settings.ligatures||!0,isEffective:(()=>{if(this.preferences.ligatures===null||this.layout===D.fixed)return!1;let e=this.metadata?.languages?.[0]?.toLowerCase();return!(e&&[`zh`,`ja`,`ko`,`mn-mong`].some(t=>e.startsWith(t)))})(),onChange:e=>{this.updatePreference(`ligatures`,e??null)}})}get lineHeight(){return new Z({initialValue:this.preferences.lineHeight,effectiveValue:this.settings.lineHeight,isEffective:this.layout!==D.fixed&&this.preferences.lineHeight!==null,onChange:e=>{this.updatePreference(`lineHeight`,e??null)},supportedRange:dl.range,step:dl.step})}get linkColor(){return new Y({initialValue:this.preferences.linkColor,effectiveValue:this.settings.linkColor||qu.linkColor,isEffective:this.layout!==D.fixed&&this.preferences.linkColor!==null,onChange:e=>{this.updatePreference(`linkColor`,e??null)}})}get maximalLineLength(){return new Z({initialValue:this.preferences.maximalLineLength,effectiveValue:this.settings.maximalLineLength,isEffective:this.layout!==D.fixed,onChange:e=>{this.updatePreference(`maximalLineLength`,e)},supportedRange:fl.range,step:fl.step})}get minimalLineLength(){return new Z({initialValue:this.preferences.minimalLineLength,effectiveValue:this.settings.minimalLineLength,isEffective:this.layout!==D.fixed,onChange:e=>{this.updatePreference(`minimalLineLength`,e)},supportedRange:fl.range,step:fl.step})}get noRuby(){return new X({initialValue:this.preferences.noRuby,effectiveValue:this.settings.noRuby||!1,isEffective:this.layout!==D.fixed&&this.metadata?.languages?.includes(`ja`)||!1,onChange:e=>{this.updatePreference(`noRuby`,e??null)}})}get optimalLineLength(){return new Z({initialValue:this.preferences.optimalLineLength,effectiveValue:this.settings.optimalLineLength,isEffective:this.layout!==D.fixed,onChange:e=>{this.updatePreference(`optimalLineLength`,e)},supportedRange:fl.range,step:fl.step})}get pageGutter(){return new Y({initialValue:this.preferences.pageGutter,effectiveValue:this.settings.pageGutter,isEffective:this.layout!==D.fixed&&!this.settings.scroll,onChange:e=>{this.updatePreference(`pageGutter`,e??null)}})}get paragraphIndent(){return new Z({initialValue:this.preferences.paragraphIndent,effectiveValue:this.settings.paragraphIndent||0,isEffective:this.layout!==D.fixed&&this.preferences.paragraphIndent!==null,onChange:e=>{this.updatePreference(`paragraphIndent`,e??null)},supportedRange:pl.range,step:pl.step})}get paragraphSpacing(){return new Z({initialValue:this.preferences.paragraphSpacing,effectiveValue:this.settings.paragraphSpacing||0,isEffective:this.layout!==D.fixed&&this.preferences.paragraphSpacing!==null,onChange:e=>{this.updatePreference(`paragraphSpacing`,e??null)},supportedRange:ml.range,step:ml.step})}get scroll(){return new X({initialValue:this.preferences.scroll,effectiveValue:this.settings.scroll||!1,isEffective:this.layout!==D.fixed,onChange:e=>{this.updatePreference(`scroll`,e??null)}})}get scrollPaddingTop(){return new Y({initialValue:this.preferences.scrollPaddingTop,effectiveValue:this.settings.scrollPaddingTop||0,isEffective:this.layout!==D.fixed&&!!this.settings.scroll&&this.preferences.scrollPaddingTop!==null,onChange:e=>{this.updatePreference(`scrollPaddingTop`,e??null)}})}get scrollPaddingBottom(){return new Y({initialValue:this.preferences.scrollPaddingBottom,effectiveValue:this.settings.scrollPaddingBottom||0,isEffective:this.layout!==D.fixed&&!!this.settings.scroll&&this.preferences.scrollPaddingBottom!==null,onChange:e=>{this.updatePreference(`scrollPaddingBottom`,e??null)}})}get scrollPaddingLeft(){return new Y({initialValue:this.preferences.scrollPaddingLeft,effectiveValue:this.settings.scrollPaddingLeft||0,isEffective:this.layout!==D.fixed&&!!this.settings.scroll&&this.preferences.scrollPaddingLeft!==null,onChange:e=>{this.updatePreference(`scrollPaddingLeft`,e??null)}})}get scrollPaddingRight(){return new Y({initialValue:this.preferences.scrollPaddingRight,effectiveValue:this.settings.scrollPaddingRight||0,isEffective:this.layout!==D.fixed&&!!this.settings.scroll&&this.preferences.scrollPaddingRight!==null,onChange:e=>{this.updatePreference(`scrollPaddingRight`,e??null)}})}get selectionBackgroundColor(){return new Y({initialValue:this.preferences.selectionBackgroundColor,effectiveValue:this.settings.selectionBackgroundColor||qu.selectionBackgroundColor,isEffective:this.layout!==D.fixed&&this.preferences.selectionBackgroundColor!==null,onChange:e=>{this.updatePreference(`selectionBackgroundColor`,e??null)}})}get selectionTextColor(){return new Y({initialValue:this.preferences.selectionTextColor,effectiveValue:this.settings.selectionTextColor||qu.selectionTextColor,isEffective:this.layout!==D.fixed&&this.preferences.selectionTextColor!==null,onChange:e=>{this.updatePreference(`selectionTextColor`,e??null)}})}get textAlign(){return new Nl({initialValue:this.preferences.textAlign,effectiveValue:this.settings.textAlign||al.start,isEffective:this.layout!==D.fixed&&this.preferences.textAlign!==null,onChange:e=>{this.updatePreference(`textAlign`,e??null)},supportedValues:Object.values(al)})}get textColor(){return new Y({initialValue:this.preferences.textColor,effectiveValue:this.settings.textColor||qu.textColor,isEffective:this.layout!==D.fixed&&this.preferences.textColor!==null,onChange:e=>{this.updatePreference(`textColor`,e??null)}})}get textNormalization(){return new X({initialValue:this.preferences.textNormalization,effectiveValue:this.settings.textNormalization||!1,isEffective:this.layout!==D.fixed,onChange:e=>{this.updatePreference(`textNormalization`,e??null)}})}get visitedColor(){return new Y({initialValue:this.preferences.visitedColor,effectiveValue:this.settings.visitedColor||qu.visitedColor,isEffective:this.layout!==D.fixed&&this.preferences.visitedColor!==null,onChange:e=>{this.updatePreference(`visitedColor`,e??null)}})}get wordSpacing(){return new Z({initialValue:this.preferences.wordSpacing,effectiveValue:this.settings.wordSpacing||0,isEffective:this.layout!==D.fixed&&this.preferences.wordSpacing!==null,onChange:e=>{this.updatePreference(`wordSpacing`,e??null)},supportedRange:hl.range,step:hl.step})}};function Yu(e){let t=getComputedStyle(e),n=parseFloat(t.paddingLeft||`0`),r=parseFloat(t.paddingRight||`0`);return e.clientWidth-n-r}function Xu(e){let t=getComputedStyle(e),n=parseFloat(t.paddingTop||`0`),r=parseFloat(t.paddingBottom||`0`);return e.clientHeight-n-r}var Zu=class extends bl{constructor(e){super(),this.a11yNormalize=e.a11yNormalize??null,this.backgroundColor=e.backgroundColor??null,this.blendFilter=e.blendFilter??null,this.bodyHyphens=e.bodyHyphens??null,this.colCount=e.colCount??null,this.darkenFilter=e.darkenFilter??null,this.deprecatedFontSize=e.deprecatedFontSize??null,this.fontFamily=e.fontFamily??null,this.fontOpticalSizing=e.fontOpticalSizing??null,this.fontSize=e.fontSize??null,this.fontSizeNormalize=e.fontSizeNormalize??null,this.fontWeight=e.fontWeight??null,this.fontWidth=e.fontWidth??null,this.invertFilter=e.invertFilter??null,this.invertGaijiFilter=e.invertGaijiFilter??null,this.iOSPatch=e.iOSPatch??null,this.iPadOSPatch=e.iPadOSPatch??null,this.letterSpacing=e.letterSpacing??null,this.ligatures=e.ligatures??null,this.lineHeight=e.lineHeight??null,this.lineLength=e.lineLength??null,this.linkColor=e.linkColor??null,this.noRuby=e.noRuby??null,this.paraIndent=e.paraIndent??null,this.paraSpacing=e.paraSpacing??null,this.selectionBackgroundColor=e.selectionBackgroundColor??null,this.selectionTextColor=e.selectionTextColor??null,this.textAlign=e.textAlign??null,this.textColor=e.textColor??null,this.view=e.view??null,this.visitedColor=e.visitedColor??null,this.wordSpacing=e.wordSpacing??null}toCSSProperties(){let e={};return this.a11yNormalize&&(e[`--USER__a11yNormalize`]=this.toFlag(`a11y`)),this.backgroundColor&&(e[`--USER__backgroundColor`]=this.backgroundColor),this.blendFilter&&(e[`--USER__blendFilter`]=this.toFlag(`blend`)),this.bodyHyphens&&(e[`--USER__bodyHyphens`]=this.bodyHyphens),this.colCount&&(e[`--USER__colCount`]=this.toUnitless(this.colCount)),this.darkenFilter===!0?e[`--USER__darkenFilter`]=this.toFlag(`darken`):typeof this.darkenFilter==`number`&&(e[`--USER__darkenFilter`]=this.toPercentage(this.darkenFilter)),this.deprecatedFontSize&&(e[`--USER__fontSizeImplementation`]=this.toFlag(`deprecatedFontSize`)),this.fontFamily&&(e[`--USER__fontFamily`]=this.fontFamily),this.fontOpticalSizing!=null&&(e[`--USER__fontOpticalSizing`]=this.fontOpticalSizing),this.fontSize!=null&&(e[`--USER__fontSize`]=this.toPercentage(this.fontSize,!0)),this.fontSizeNormalize&&(e[`--USER__fontSizeNormalize`]=this.toFlag(`normalize`)),this.fontWeight!=null&&(e[`--USER__fontWeight`]=this.toUnitless(this.fontWeight)),this.fontWidth!=null&&(e[`--USER__fontWidth`]=typeof this.fontWidth==`string`?this.fontWidth:this.toUnitless(this.fontWidth)),this.invertFilter===!0?e[`--USER__invertFilter`]=this.toFlag(`invert`):typeof this.invertFilter==`number`&&(e[`--USER__invertFilter`]=this.toPercentage(this.invertFilter)),this.invertGaijiFilter===!0?e[`--USER__invertGaiji`]=this.toFlag(`invertGaiji`):typeof this.invertGaijiFilter==`number`&&(e[`--USER__invertGaiji`]=this.toPercentage(this.invertGaijiFilter)),this.iOSPatch&&(e[`--USER__iOSPatch`]=this.toFlag(`iOSPatch`)),this.iPadOSPatch&&(e[`--USER__iPadOSPatch`]=this.toFlag(`iPadOSPatch`)),this.letterSpacing!=null&&(e[`--USER__letterSpacing`]=this.toRem(this.letterSpacing)),this.ligatures&&(e[`--USER__ligatures`]=this.ligatures),this.lineHeight!=null&&(e[`--USER__lineHeight`]=this.toUnitless(this.lineHeight)),this.lineLength!=null&&(e[`--USER__lineLength`]=this.toPx(this.lineLength)),this.linkColor&&(e[`--USER__linkColor`]=this.linkColor),this.noRuby&&(e[`--USER__noRuby`]=this.toFlag(`noRuby`)),this.paraIndent!=null&&(e[`--USER__paraIndent`]=this.toRem(this.paraIndent)),this.paraSpacing!=null&&(e[`--USER__paraSpacing`]=this.toRem(this.paraSpacing)),this.selectionBackgroundColor&&(e[`--USER__selectionBackgroundColor`]=this.selectionBackgroundColor),this.selectionTextColor&&(e[`--USER__selectionTextColor`]=this.selectionTextColor),this.textAlign&&(e[`--USER__textAlign`]=this.textAlign),this.textColor&&(e[`--USER__textColor`]=this.textColor),this.view&&(e[`--USER__view`]=this.toFlag(this.view)),this.visitedColor&&(e[`--USER__visitedColor`]=this.visitedColor),this.wordSpacing!=null&&(e[`--USER__wordSpacing`]=this.toRem(this.wordSpacing)),e}},Qu=class extends bl{constructor(e){super(),this.backgroundColor=e.backgroundColor??null,this.baseFontFamily=e.baseFontFamily??null,this.baseFontSize=e.baseFontSize??null,this.baseLineHeight=e.baseLineHeight??null,this.boxSizingMedia=e.boxSizingMedia??null,this.boxSizingTable=e.boxSizingTable??null,this.colWidth=e.colWidth??null,this.colCount=e.colCount??null,this.colGap=e.colGap??null,this.codeFontFamily=e.codeFontFamily??null,this.compFontFamily=e.compFontFamily??null,this.defaultLineLength=e.defaultLineLength??null,this.flowSpacing=e.flowSpacing??null,this.humanistTf=e.humanistTf??null,this.linkColor=e.linkColor??null,this.maxMediaWidth=e.maxMediaWidth??null,this.maxMediaHeight=e.maxMediaHeight??null,this.modernTf=e.modernTf??null,this.monospaceTf=e.monospaceTf??null,this.noOverflow=e.noOverflow??null,this.noVerticalPagination=e.noVerticalPagination??null,this.oldStyleTf=e.oldStyleTf??null,this.pageGutter=e.pageGutter??null,this.paraIndent=e.paraIndent??null,this.paraSpacing=e.paraSpacing??null,this.primaryColor=e.primaryColor??null,this.scrollPaddingBottom=e.scrollPaddingBottom??null,this.scrollPaddingLeft=e.scrollPaddingLeft??null,this.scrollPaddingRight=e.scrollPaddingRight??null,this.scrollPaddingTop=e.scrollPaddingTop??null,this.sansSerifJa=e.sansSerifJa??null,this.sansSerifJaV=e.sansSerifJaV??null,this.sansTf=e.sansTf??null,this.secondaryColor=e.secondaryColor??null,this.selectionBackgroundColor=e.selectionBackgroundColor??null,this.selectionTextColor=e.selectionTextColor??null,this.serifJa=e.serifJa??null,this.serifJaV=e.serifJaV??null,this.textColor=e.textColor??null,this.typeScale=e.typeScale??null,this.visitedColor=e.visitedColor??null,this.experiments=e.experiments??null}toCSSProperties(){let e={};return this.backgroundColor&&(e[`--RS__backgroundColor`]=this.backgroundColor),this.baseFontFamily&&(e[`--RS__baseFontFamily`]=this.baseFontFamily),this.baseFontSize!=null&&(e[`--RS__baseFontSize`]=this.toRem(this.baseFontSize)),this.baseLineHeight!=null&&(e[`--RS__baseLineHeight`]=this.toUnitless(this.baseLineHeight)),this.boxSizingMedia&&(e[`--RS__boxSizingMedia`]=this.boxSizingMedia),this.boxSizingTable&&(e[`--RS__boxSizingTable`]=this.boxSizingTable),this.colWidth!=null&&(e[`--RS__colWidth`]=this.colWidth),this.colCount!=null&&(e[`--RS__colCount`]=this.toUnitless(this.colCount)),this.colGap!=null&&(e[`--RS__colGap`]=this.toPx(this.colGap)),this.codeFontFamily&&(e[`--RS__codeFontFamily`]=this.codeFontFamily),this.compFontFamily&&(e[`--RS__compFontFamily`]=this.compFontFamily),this.defaultLineLength!=null&&(e[`--RS__defaultLineLength`]=this.toPx(this.defaultLineLength)),this.flowSpacing!=null&&(e[`--RS__flowSpacing`]=this.toRem(this.flowSpacing)),this.humanistTf&&(e[`--RS__humanistTf`]=this.humanistTf),this.linkColor&&(e[`--RS__linkColor`]=this.linkColor),this.maxMediaWidth&&(e[`--RS__maxMediaWidth`]=this.toVw(this.maxMediaWidth)),this.maxMediaHeight&&(e[`--RS__maxMediaHeight`]=this.toVh(this.maxMediaHeight)),this.modernTf&&(e[`--RS__modernTf`]=this.modernTf),this.monospaceTf&&(e[`--RS__monospaceTf`]=this.monospaceTf),this.noOverflow&&(e[`--RS__disableOverflow`]=this.toFlag(`noOverflow`)),this.noVerticalPagination&&(e[`--RS__disablePagination`]=this.toFlag(`noVerticalPagination`)),this.oldStyleTf&&(e[`--RS__oldStyleTf`]=this.oldStyleTf),this.pageGutter!=null&&(e[`--RS__pageGutter`]=this.toPx(this.pageGutter)),this.paraIndent!=null&&(e[`--RS__paraIndent`]=this.toRem(this.paraIndent)),this.paraSpacing!=null&&(e[`--RS__paraSpacing`]=this.toRem(this.paraSpacing)),this.primaryColor&&(e[`--RS__primaryColor`]=this.primaryColor),this.sansSerifJa&&(e[`--RS__sans-serif-ja`]=this.sansSerifJa),this.sansSerifJaV&&(e[`--RS__sans-serif-ja-v`]=this.sansSerifJaV),this.sansTf&&(e[`--RS__sansTf`]=this.sansTf),this.scrollPaddingBottom!=null&&(e[`--RS__scrollPaddingBottom`]=this.toPx(this.scrollPaddingBottom)),this.scrollPaddingLeft!=null&&(e[`--RS__scrollPaddingLeft`]=this.toPx(this.scrollPaddingLeft)),this.scrollPaddingRight!=null&&(e[`--RS__scrollPaddingRight`]=this.toPx(this.scrollPaddingRight)),this.scrollPaddingTop!=null&&(e[`--RS__scrollPaddingTop`]=this.toPx(this.scrollPaddingTop)),this.secondaryColor&&(e[`--RS__secondaryColor`]=this.secondaryColor),this.selectionBackgroundColor&&(e[`--RS__selectionBackgroundColor`]=this.selectionBackgroundColor),this.selectionTextColor&&(e[`--RS__selectionTextColor`]=this.selectionTextColor),this.serifJa&&(e[`--RS__serif-ja`]=this.serifJa),this.serifJaV&&(e[`--RS__serif-ja-v`]=this.serifJaV),this.textColor&&(e[`--RS__textColor`]=this.textColor),this.typeScale&&(e[`--RS__typeScale`]=this.toUnitless(this.typeScale)),this.visitedColor&&(e[`--RS__visitedColor`]=this.visitedColor),this.experiments&&this.experiments.forEach(t=>{e[`--RS__`+t]=nl[t].value}),e}},$u=class{constructor(e){this.rsProperties=e.rsProperties,this.userProperties=e.userProperties,this.lineLengths=e.lineLengths,this.container=e.container,this.containerParent=e.container.parentElement||document.documentElement,this.constraint=e.constraint,this.isCJKVertical=e.isCJKVertical??!1,this.cachedColCount=e.userProperties.colCount,this.effectiveContainerWidth=Yu(this.containerParent)}update(e){this.cachedColCount=e.columnCount,e.constraint!==this.constraint&&(this.constraint=e.constraint),e.pageGutter!==this.rsProperties.pageGutter&&(this.rsProperties.pageGutter=e.pageGutter),e.scrollPaddingBottom!==this.rsProperties.scrollPaddingBottom&&(this.rsProperties.scrollPaddingBottom=e.scrollPaddingBottom),e.scrollPaddingLeft!==this.rsProperties.scrollPaddingLeft&&(this.rsProperties.scrollPaddingLeft=e.scrollPaddingLeft),e.scrollPaddingRight!==this.rsProperties.scrollPaddingRight&&(this.rsProperties.scrollPaddingRight=e.scrollPaddingRight),e.scrollPaddingTop!==this.rsProperties.scrollPaddingTop&&(this.rsProperties.scrollPaddingTop=e.scrollPaddingTop),e.experiments!==this.rsProperties.experiments&&(this.rsProperties.experiments=e.experiments),this.lineLengths.update({fontFace:e.fontFamily,letterSpacing:e.letterSpacing,padding:e.scroll?(e.scrollPaddingLeft||0)+(e.scrollPaddingRight||0):(e.pageGutter||0)*2,wordSpacing:e.wordSpacing,optimalChars:e.optimalLineLength,minChars:e.minimalLineLength,maxChars:e.maximalLineLength});let t=this.updateLayout(e.fontSize,e.deprecatedFontSize||e.iOSPatch,e.scroll,e.columnCount);t?.effectiveContainerWidth&&(this.effectiveContainerWidth=t?.effectiveContainerWidth);let n={a11yNormalize:e.textNormalization,backgroundColor:e.backgroundColor,blendFilter:e.blendFilter,bodyHyphens:typeof e.hyphens==`boolean`?e.hyphens?`auto`:`none`:null,colCount:t?.colCount,darkenFilter:e.darkenFilter,deprecatedFontSize:e.deprecatedFontSize,fontFamily:e.fontFamily,fontOpticalSizing:typeof e.fontOpticalSizing==`boolean`?e.fontOpticalSizing?`auto`:`none`:null,fontSize:e.fontSize,fontSizeNormalize:e.fontSizeNormalize,fontWeight:e.fontWeight,fontWidth:e.fontWidth,invertFilter:e.invertFilter,invertGaijiFilter:e.invertGaijiFilter,iOSPatch:e.iOSPatch,iPadOSPatch:e.iPadOSPatch,letterSpacing:e.letterSpacing,ligatures:typeof e.ligatures==`boolean`?e.ligatures?`common-ligatures`:`none`:null,lineHeight:e.lineHeight,lineLength:t?.effectiveLineLength,linkColor:e.linkColor,noRuby:e.noRuby,paraIndent:e.paragraphIndent,paraSpacing:e.paragraphSpacing,selectionBackgroundColor:e.selectionBackgroundColor,selectionTextColor:e.selectionTextColor,textAlign:e.textAlign,textColor:e.textColor,view:typeof e.scroll==`boolean`?e.scroll?`scroll`:`paged`:null,visitedColor:e.visitedColor,wordSpacing:e.wordSpacing};this.userProperties=new Zu(n)}updateLayout(e,t,n,r){return this.isCJKVertical?this.computeCJKVerticalLength(e,t):n??this.userProperties.view===`scroll`?this.computeScrollLength(e,t):this.paginate(e,t,r)}getCompensatedMetrics(e,t){let n=e||this.userProperties.fontSize||1;return{zoomFactor:n,zoomCompensation:n<1?1/n:t?n:1,optimal:Math.round(this.lineLengths.optimalLineLength)*n,minimal:this.lineLengths.minimalLineLength===null?null:Math.round(this.lineLengths.minimalLineLength*n),maximal:this.lineLengths.maximalLineLength===null?null:Math.round(this.lineLengths.maximalLineLength*n)}}paginate(e,t,n){let r=Math.round(Yu(this.containerParent)-this.constraint),{zoomCompensation:i,optimal:a,minimal:o,maximal:s}=this.getCompensatedMetrics(e,t),c=()=>r>=a&&s!==null?Math.min(Math.round(s*i),r):r,l=1,u=r;if(n===void 0)return{colCount:void 0,effectiveContainerWidth:u,effectiveLineLength:Math.round(u/l*i)};if(n===null){if(r>=a&&s!==null){l=Math.floor(r/a);let e=Math.round(s*i*l);u=Math.min(e,r)}else u=c()}else if(n>1){if(r>=Math.round(n*(o===null?a:o))){if(l=n,s===null)u=r;else{let e=Math.round(s*i*l);u=Math.min(e,r)}}else if(o!==null&&r<Math.round(n*o)){if(l=Math.floor(r/o),l<=1)l=1,u=c();else{let e=Math.round(a*i*l);u=Math.min(e,r)}}else{l=n;let e=Math.round(a*i*l);u=Math.min(e,r)}}else l=1,u=c();return{colCount:l,effectiveContainerWidth:u,effectiveLineLength:Math.round(u/l/(e&&e>=1?e:1)*i)}}computeCJKVerticalLength(e,t){let n=Math.round(Yu(this.containerParent)-this.constraint),r=Math.round(Xu(this.containerParent)),i=this.getCompensatedMetrics(e,t);return{colCount:void 0,effectiveContainerWidth:n,effectiveLineLength:i.maximal===null?r:Math.min(Math.round(i.maximal*i.zoomCompensation),r)}}computeScrollLength(e,t){let n=Math.round(Yu(this.containerParent)-this.constraint),r=this.getCompensatedMetrics(e&&(e<1||t)?e:1,t),i=r.zoomCompensation,a=r.optimal,o=r.maximal,s,c=n,l=Math.round(a*i);if(o===null)l=n;else{let e=Math.min(Math.round(o*i),n);l=t?e:Math.round(e*i)}return{colCount:s,effectiveContainerWidth:c,effectiveLineLength:l}}setContainerWidth(){this.container.style.width=`${this.effectiveContainerWidth}px`}resizeHandler(){let e=this.updateLayout(this.userProperties.fontSize,this.userProperties.deprecatedFontSize||this.userProperties.iOSPatch,this.userProperties.view===`scroll`,this.cachedColCount);this.userProperties.colCount=e.colCount,this.userProperties.lineLength=e.effectiveLineLength,this.effectiveContainerWidth=e.effectiveContainerWidth,this.container.style.width=`${this.effectiveContainerWidth}px`}},ed=`modulepreload`,td=function(e){return`/`+e},nd={},$=function(e,t,n){let r=Promise.resolve();if(t&&t.length>0){let e=function(e){return Promise.all(e.map(e=>Promise.resolve(e).then(e=>({status:`fulfilled`,value:e}),e=>({status:`rejected`,reason:e}))))};document.getElementsByTagName(`link`);let n=document.querySelector(`meta[property=csp-nonce]`),i=n?.nonce||n?.getAttribute(`nonce`);r=e(t.map(e=>{if(e=td(e),e in nd)return;nd[e]=!0;let t=e.endsWith(`.css`),n=t?`[rel="stylesheet"]`:``;if(document.querySelector(`link[href="${e}"]${n}`))return;let r=document.createElement(`link`);if(r.rel=t?`stylesheet`:ed,t||(r.as=`script`),r.crossOrigin=``,r.href=e,i&&r.setAttribute(`nonce`,i),document.head.appendChild(r),t)return new Promise((t,n)=>{r.addEventListener(`load`,t),r.addEventListener(`error`,()=>n(Error(`Unable to preload CSS for ${e}`)))})}))}function i(e){let t=new Event(`vite:preloadError`,{cancelable:!0});if(t.payload=e,window.dispatchEvent(t),!t.defaultPrevented)throw e}return r.then(t=>{for(let e of t||[])e.status===`rejected`&&i(e.reason);return e().catch(i)})},rd=`// Note: we aren't blocking some of the events right now to try and be as nonintrusive as possible.
// For a more comprehensive implementation, see https://github.com/hackademix/noscript/blob/3a83c0e4a506f175e38b0342dad50cdca3eae836/src/content/syncFetchPolicy.js#L142
// The snippet of code at the beginning of this source is an attempt at defence against JS using persistent storage
(function() {
    const noop = () => {}, emptyObj = {}, emptyPromise = () => Promise.resolve(void 0), fakeStorage = {
        getItem: noop, 
        setItem: noop, 
        removeItem: noop, 
        clear: noop, 
        key: noop, 
        length: 0
    };
    
    ["localStorage", "sessionStorage"].forEach((e) => Object.defineProperty(window, e, {
        get: () => fakeStorage,
        configurable: !0
    }));
    
    Object.defineProperty(document, "cookie", {
        get: () => "",
        set: noop,
        configurable: !0
    });
    
    Object.defineProperty(window, "indexedDB", {
        get: () => {},
        configurable: !0
    });
    
    Object.defineProperty(window, "caches", {
        get: () => emptyObj,
        configurable: !0
    });
    
    Object.defineProperty(navigator, "storage", {
        get: () => ({
            persist: emptyPromise,
            persisted: emptyPromise,
            estimate: () => Promise.resolve({quota: 0, usage: 0})
        }),
        configurable: !0
    });
    
    Object.defineProperty(navigator, "serviceWorker", {
        get: () => ({
            register: emptyPromise,
            getRegistration: emptyPromise,
            ready: emptyPromise()
        }),
        configurable: !0
    });

    window._readium_blockedEvents = [];
    window._readium_blockEvents = true;
    window._readium_eventBlocker = (e) => {
        if(!window._readium_blockEvents) return;
        e.preventDefault();
        e.stopImmediatePropagation();
        _readium_blockedEvents.push([
            1, e, e.currentTarget || e.target
        ]);
    };
    window.addEventListener("DOMContentLoaded", window._readium_eventBlocker, true);
    window.addEventListener("load", window._readium_eventBlocker, true);
})();
`,id=r({default:()=>ad}),ad,od=n((()=>{ad=`/*!
 * Readium CSS v.2.0.5
 * Copyright (c) 2017–2026. Readium Foundation. All rights reserved.
 * Use of this source code is governed by a BSD-style license which is detailed in the
 * LICENSE file present in the project repository where this source code is maintained.
 * Core maintainer: Jiminy Panoz <jiminy.panoz@edrlab.org> 
 * Contributors: 
 * Daniel Weck
 * Hadrien Gardeur
 * Innovimax
 * L. Le Meur
 * Mickaël Menu
 * k_taka
 */

@namespace url("http://www.w3.org/1999/xhtml");

@namespace epub url("http://www.idpf.org/2007/ops");

@namespace m url("http://www.w3.org/1998/Math/MathML");

@namespace svg url("http://www.w3.org/2000/svg");

@-ms-viewport{
  width:device-width;
}

@viewport{
  width:device-width;
  zoom:1;
}

:root{

  --RS__sans-serif-ja-v:'Hiragino Sans', 'Hiragino Kaku Gothic ProN', 'Hiragino Kaku Gothic Pro', 'ヒラギノ角ゴ W3', 'YuGothic', 'Yu Gothic Medium', 'BIZ UDGothic', 'Yu Gothic', 'ＭＳゴシック', 'MS Gothic', sans-serif;

  --RS__serif-ja-v:'Hiragino Mincho ProN', 'Hiragino Mincho Pro', 'YuMincho', 'BIZ UDMincho', 'Yu Mincho', 'ＭＳ明朝', 'MS Mincho', serif;

  --RS__sans-serif-ja:'Hiragino Sans', 'Hiragino Kaku Gothic ProN', 'Hiragino Kaku Gothic Pro', 'ヒラギノ角ゴ W3', 'YuGothic', 'Yu Gothic Medium', 'BIZ UDPGothic', 'Yu Gothic', 'ＭＳ Ｐゴシック', 'MS PGothic', sans-serif;

  --RS__serif-ja:'Hiragino Mincho ProN', 'Hiragino Mincho Pro', 'YuMincho', 'BIZ UDPMincho', 'Yu Mincho', 'ＭＳ Ｐ明朝', 'MS PMincho', serif;

  --RS__monospaceTf:ui-monospace, 'Andale Mono', 'Cascadia Code', 'Source Code Pro', Menlo, Consolas, 'DejaVu Sans Mono', monospace;

  --RS__humanistTf:Seravek, Calibri, 'Gill Sans Nova', Roboto, Ubuntu, 'DejaVu Sans', source-sans-pro, sans-serif;

  --RS__sansTf:-ui-sans-serif, -apple-system, system-ui, BlinkMacSystemFont, 'Segoe UI Variable', 'Segoe UI', Inter, Roboto, 'Helvetica Neue', 'Arial Nova', 'Liberation Sans', Arial, sans-serif;

  --RS__modernTf:Athelas, Constantia, Charter, 'Bitstream Charter', Cambria, 'Georgia Pro', Georgia, serif;

  --RS__oldStyleTf:'Iowan Old Style', Sitka, 'Sitka Text', Palatino, 'Book Antiqua', 'URW Palladio L', P052, serif;

  --RS__zh-HK-lineHeightCompensation:1.167;

  --RS__zh-HK-baseFontFamily:'方體', 'PingFang HK', '方體', 'PingFang TC', '黑體', 'Heiti TC', 'Microsoft JhengHei UI', 'Microsoft JhengHei', Roboto, Noto, 'Noto Sans CJK TC', sans-serif;

  --RS__zh-TW-lineHeightCompensation:1.167;

  --RS__zh-TW-baseFontFamily:'方體', 'PingFang TC', '黑體', 'Heiti TC', 'Microsoft JhengHei UI', 'Microsoft JhengHei', Roboto, Noto, 'Noto Sans CJK TC', sans-serif;

  --RS__zh-Hant-lineHeightCompensation:1.167;

  --RS__zh-Hant-baseFontFamily:'方體', 'PingFang TC', '黑體', 'Heiti TC', 'Microsoft JhengHei UI', 'Microsoft JhengHei', Roboto, Noto, 'Noto Sans CJK TC', sans-serif;

  --RS__zh-lineHeightCompensation:1.167;

  --RS__zh-baseFontFamily:'方体', 'PingFang SC', '黑体', 'Heiti SC', 'Microsoft JhengHei UI', 'Microsoft JhengHei', Roboto, Noto, 'Noto Sans CJK SC', sans-serif;

  --RS__th-lineHeightCompensation:1.067;

  --RS__th-baseFontFamily:Thonburi, 'Leelawadee UI', 'Cordia New', Roboto, Noto, 'Noto Sans Thai', sans-serif;

  --RS__te-baseFontFamily:'Kohinoor Telugu', 'Telugu Sangam MN', 'Nirmala UI', Gautami, Roboto, Noto, 'Noto Sans Telugu', sans-serif;

  --RS__ta-lineHeightCompensation:1.067;

  --RS__ta-baseFontFamily:'Tamil Sangam MN', 'Nirmala UI', Latha, Roboto, Noto, 'Noto Sans Tamil', sans-serif;

  --RS__si-lineHeightCompensation:1.167;

  --RS__si-baseFontFamily:'Sinhala Sangam MN', 'Nirmala UI', 'Iskoola Pota', Roboto, Noto, 'Noto Sans Sinhala', sans-serif;

  --RS__pa-lineHeightCompensation:1.1;

  --RS__pa-baseFontFamily:'Gurmukhi MN', 'Nirmala UI', Kartika, Roboto, Noto, 'Noto Sans Gurmukhi', sans-serif;

  --RS__or-lineHeightCompensation:1.167;

  --RS__or-baseFontFamily:'Oriya Sangam MN', 'Nirmala UI', Kalinga, Roboto, Noto, 'Noto Sans Oriya', sans-serif;

  --RS__ml-lineHeightCompensation:1.067;

  --RS__ml-baseFontFamily:'Malayalam Sangam MN', 'Nirmala UI', Kartika, Roboto, Noto, 'Noto Sans Malayalam', sans-serif;

  --RS__lo-baseFontFamily:'Lao Sangam MN', 'Leelawadee UI', 'Lao UI', Roboto, Noto, 'Noto Sans Lao', sans-serif;

  --RS__ko-lineHeightCompensation:1.167;

  --RS__ko-baseFontFamily:'Nanum Gothic', 'Apple SD Gothic Neo', 'Malgun Gothic', Roboto, Noto, 'Noto Sans CJK KR', sans-serif;

  --RS__kn-lineHeightCompensation:1.1;

  --RS__kn-baseFontFamily:'Kannada Sangam MN', 'Nirmala UI', Tunga, Roboto, Noto, 'Noto Sans Kannada', sans-serif;

  --RS__km-lineHeightCompensation:1.067;

  --RS__km-baseFontFamily:'Khmer Sangam MN', 'Leelawadee UI', 'Khmer UI', Roboto, Noto, 'Noto Sans Khmer', sans-serif;

  --RS__ja-lineHeightCompensation:1.167;

  --RS__ja-baseFontFamily:YuGothic, 'Hiragino Maru Gothic ProN', 'Hiragino Sans', 'Yu Gothic UI', 'Meiryo UI', 'MS Gothic', Roboto, Noto, 'Noto Sans CJK JP', sans-serif;

  --RS__iu-baseFontFamily:'Euphemia UCAS', Euphemia, Roboto, Noto, 'Noto Sans Canadian Aboriginal', sans-serif;

  --RS__hy-baseFontFamily:Mshtakan, Sylfaen, Roboto, Noto, 'Noto Serif Armenian', serif;

  --RS__hi-lineHeightCompensation:1.1;

  --RS__hi-baseFontFamily:'Kohinoor Devanagari', 'Devanagari Sangam MN', Kokila, 'Nirmala UI', Roboto, Noto, 'Noto Sans Devanagari', sans-serif;

  --RS__he-lineHeightCompensation:1.1;

  --RS__he-baseFontFamily:'New Peninim MT', 'Arial Hebrew', Gisha, 'Times New Roman', Roboto, Noto, 'Noto Sans Hebrew', sans-serif;

  --RS__gu-lineHeightCompensation:1.167;

  --RS__gu-baseFontFamily:'Gujarati Sangam MN', 'Nirmala UI', Shruti, Roboto, Noto, 'Noto Sans Gujarati', sans-serif;

  --RS__fa-baseFontFamily:'Geeza Pro', 'Arabic Typesetting', Roboto, Noto, 'Noto Naskh Arabic', 'Times New Roman', serif;

  --RS__chr-lineHeightCompensation:1.167;

  --RS__chr-baseFontFamily:'Plantagenet Cherokee', Roboto, Noto, 'Noto Sans Cherokee';

  --RS__bo-baseFontFamily:Kailasa, 'Microsoft Himalaya', Roboto, Noto, 'Noto Sans Tibetan', sans-serif;

  --RS__bn-lineHeightCompensation:1.067;

  --RS__bn-baseFontFamily:'Kohinoor Bangla', 'Bangla Sangam MN', Vrinda, Roboto, Noto, 'Noto Sans Bengali', sans-serif;

  --RS__ar-baseFontFamily:'Geeza Pro', 'Arabic Typesetting', Roboto, Noto, 'Noto Naskh Arabic', 'Times New Roman', serif;

  --RS__am-lineHeightCompensation:1.167;

  --RS__am-baseFontFamily:Kefa, Nyala, Roboto, Noto, 'Noto Sans Ethiopic', serif;

  --RS__latin-lineHeightCompensation:1;

  --RS__latin-baseFontFamily:var(--RS__oldStyleTf);
  --RS__baseFontFamily:var(--RS__latin-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__latin-lineHeightCompensation);
  --RS__baseLineHeight:calc(1.5 * var(--RS__lineHeightCompensation));

  --RS__selectionTextColor:inherit;

  --RS__selectionBackgroundColor:#b4d8fe;

  --RS__visitedColor:#551A8B;

  --RS__linkColor:#0000EE;

  --RS__textColor:#121212;

  --RS__backgroundColor:#FFFFFF;
  color:var(--RS__textColor) !important;

  background-color:var(--RS__backgroundColor) !important;
}

::-moz-selection{
  color:var(--RS__selectionTextColor);
  background-color:var(--RS__selectionBackgroundColor);
}

::selection{
  color:var(--RS__selectionTextColor);
  background-color:var(--RS__selectionBackgroundColor);
}

html{
  font-family:var(--RS__baseFontFamily);
  line-height:1.6;
  line-height:var(--RS__baseLineHeight);
  text-rendering:optimizelegibility;
}

h1, h2, h3{
  line-height:normal;
}

:lang(ja),
:lang(zh),
:lang(ko){
  word-wrap:break-word;
  -webkit-line-break:strict;
  -epub-line-break:strict;
  line-break:strict;
}

math{
  font-family:"Latin Modern Math", "STIX Two Math", "XITS Math", "STIX Math", "Libertinus Math", "TeX Gyre Termes Math", "TeX Gyre Bonum Math", "TeX Gyre Schola", "DejaVu Math TeX Gyre", "TeX Gyre Pagella Math", "Asana Math", "Cambria Math", "Lucida Bright Math", "Minion Math", STIXGeneral, STIXSizeOneSym, Symbol, "Times New Roman", serif;
}

:lang(am){
  --RS__baseFontFamily:var(--RS__am-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__am-lineHeightCompensation);
}

:lang(ar){
  --RS__baseFontFamily:var(--RS__ar-baseFontFamily);
}

:lang(bn){
  --RS__baseFontFamily:var(--RS__bn-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__bn-lineHeightCompensation);
}

:lang(bo){
  --RS__baseFontFamily:var(--RS__bo-baseFontFamily);
}

:lang(chr){
  --RS__baseFontFamily:var(--RS__chr-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__chr-lineHeightCompensation);
}

:lang(fa){
  --RS__baseFontFamily:var(--RS__fa-baseFontFamily);
}

:lang(gu){
  --RS__baseFontFamily:var(--RS__gu-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__gu-lineHeightCompensation);
}

:lang(he){
  --RS__baseFontFamily:var(--RS__he-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__he-lineHeightCompensation);
}

:lang(hi){
  --RS__baseFontFamily:var(--RS__hi-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__hi-lineHeightCompensation);
}

:lang(hy){
  --RS__baseFontFamily:var(--RS__hy-baseFontFamily);
}

:lang(iu){
  --RS__baseFontFamily:var(--RS__iu-baseFontFamily);
}

:lang(ja){
  --RS__baseFontFamily:var(--RS__ja-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__ja-lineHeightCompensation);
}

:lang(km){
  --RS__baseFontFamily:var(--RS__km-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__km-lineHeightCompensation);
}

:lang(kn){
  --RS__baseFontFamily:var(--RS__kn-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__kn-lineHeightCompensation);
}

:lang(ko){
  --RS__baseFontFamily:var(--RS__ko-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__ko-lineHeightCompensation);
}

:lang(lo){
  --RS__baseFontFamily:var(--RS__lo-baseFontFamily);
}

:lang(ml){
  --RS__baseFontFamily:var(--RS__ml-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__ml-lineHeightCompensation);
}

:lang(or){
  --RS__baseFontFamily:var(--RS__or-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__or-lineHeightCompensation);
}

:lang(pa){
  --RS__baseFontFamily:var(--RS__pa-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__pa-lineHeightCompensation);
}

:lang(si){
  --RS__baseFontFamily:var(--RS__si-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__si-lineHeightCompensation);
}

:lang(ta){
  --RS__baseFontFamily:var(--RS__ta-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__ta-lineHeightCompensation);
}

:lang(te){
  --RS__baseFontFamily:var(--RS__te-baseFontFamily);
}

:lang(th){
  --RS__baseFontFamily:var(--RS__th-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__th-lineHeightCompensation);
}

:lang(zh){
  --RS__baseFontFamily:var(--RS__zh-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__zh-lineHeightCompensation);
}

:lang(zh-Hant){
  --RS__baseFontFamily:var(--RS__zh-Hant-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__zh-Hant-lineHeightCompensation);
}

:lang(zh-TW){
  --RS__baseFontFamily:var(--RS__zh-TW-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__zh-TW-lineHeightCompensation);
}

:lang(zh-HK){
  --RS__baseFontFamily:var(--RS__zh-HK-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__zh-HK-lineHeightCompensation);
}

body{
  widows:2;
  orphans:2;
}

figcaption, th, td{
  widows:1;
  orphans:1;
}

h2, h3, h4, h5, h6, dt,
hr, caption{
  -webkit-column-break-after:avoid;
  page-break-after:avoid;
  break-after:avoid;
}

h1, h2, h3, h4, h5, h6, dt,
figure, tr{
  -webkit-column-break-inside:avoid;
  page-break-inside:avoid;
  break-inside:avoid;
}

body{
  -webkit-hyphenate-character:"\\002D";
  -moz-hyphenate-character:"\\002D";
  -ms-hyphenate-character:"\\002D";
  hyphenate-character:"\\002D";
  -webkit-hyphenate-limit-lines:3;
  -ms-hyphenate-limit-lines:3;
  hyphenate-limit-lines:3;
}

h1, h2, h3, h4, h5, h6, dt,
figcaption, pre, caption, address,
center, code, var{
  -ms-hyphens:none;
  -moz-hyphens:none;
  -webkit-hyphens:none;
  -epub-hyphens:none;
  hyphens:none;
}

body{
  font-variant-numeric:oldstyle-nums proportional-nums;
}

:lang(ja) body,
:lang(zh) body,
:lang(ko) body{
  font-variant-numeric:lining-nums proportional-nums;
}

h1, h2, h3, h4, h5, h6, dt{
  font-variant-numeric:lining-nums proportional-nums;
}

table{
  font-variant-numeric:lining-nums tabular-nums;
}

code, var{
  font-variant-ligatures:none;
  font-variant-numeric:lining-nums tabular-nums slashed-zero;
}

rt{
  font-variant-east-asian:ruby;
}

:lang(ar){
  font-variant-ligatures:common-ligatures;
}

:lang(ko){
  font-kerning:normal;
}

hr{
  color:inherit;
  border-color:currentcolor;
}

table, th, td{
  border-color:currentcolor;
}

figure, blockquote{
  margin:1em 5%;
}

ul, ol{
  padding-left:5%;
}

dd{
  margin-left:5%;
}

pre{
  white-space:pre-wrap;
  -ms-tab-size:2;
  -moz-tab-size:2;
  -webkit-tab-size:2;
  tab-size:2;
}

abbr[title], acronym[title]{
  text-decoration:dotted underline;
}

nobr wbr{
  white-space:normal;
}

ruby > rt, ruby > rp{
  -webkit-user-select:none;
  -moz-user-select:none;
  -ms-user-select:none;
  user-select:none;
}

*:lang(ja):not(:lang(ja-Latn)):not(:lang(ja-Cyrl)),
*:lang(zh):not(:lang(zh-Latn)):not(:lang(zh-Cyrl)),
*:lang(ko):not(:lang(ko-Latn)):not(:lang(ko-Cyrl)),
:lang(ja):not(:lang(ja-Latn)):not(:lang(ja-Cyrl)) cite, 
:lang(ja):not(:lang(ja-Latn)):not(:lang(ja-Cyrl)) dfn, 
:lang(ja):not(:lang(ja-Latn)):not(:lang(ja-Cyrl)) em, 
:lang(ja):not(:lang(ja-Latn)):not(:lang(ja-Cyrl)) i,
:lang(zh):not(:lang(zh-Latn)):not(:lang(zh-Cyrl)) cite, 
:lang(zh):not(:lang(zh-Latn)):not(:lang(zh-Cyrl)) dfn, 
:lang(zh):not(:lang(zh-Latn)):not(:lang(zh-Cyrl)) em, 
:lang(zh):not(:lang(zh-Latn)):not(:lang(zh-Cyrl)) i,
:lang(ko):not(:lang(ko-Latn)):not(:lang(ko-Cyrl)) cite, 
:lang(ko):not(:lang(ko-Latn)):not(:lang(ko-Cyrl)) dfn, 
:lang(ko):not(:lang(ko-Latn)):not(:lang(ko-Cyrl)) em, 
:lang(ko):not(:lang(ko-Latn)):not(:lang(ko-Cyrl)) i{
  font-style:normal;
}

:lang(ja) a,
:lang(zh) a,
:lang(ko) a{
  text-decoration:none;
}

:root{
  --RS__maxMediaWidth:100%;
  --RS__maxMediaHeight:95vh;
  --RS__boxSizingMedia:border-box;
  --RS__boxSizingTable:border-box;
}

a, a span, span a, h1, h2, h3, h4, h5, h6{
  word-wrap:break-word;
}

div{
  max-width:var(--RS__maxMediaWidth);
}

img, svg|svg, video{
  object-fit:contain;

  width:auto;
  height:auto;
  max-width:var(--RS__maxMediaWidth);
  max-height:var(--RS__maxMediaHeight) !important;
  box-sizing:var(--RS__boxSizingMedia);
  -webkit-column-break-inside:avoid;
  page-break-inside:avoid;
  break-inside:avoid;
}

@supports (zoom: 1) and (not ((-webkit-column-axis: horizontal) and (-webkit-column-progression: normal))){

  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] img,
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] svg|svg,
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] video{
    zoom:calc(100% / var(--USER__fontSize));
  }
}

audio{
    max-width:100%;
    -webkit-column-break-inside:avoid;
    page-break-inside:avoid;
    break-inside:avoid;
  }

table{
  max-width:var(--RS__maxMediaWidth);
  box-sizing:var(--RS__boxSizingTable);
}`})),sd=r({default:()=>cd}),cd,ld=n((()=>{cd=`/*!
 * Readium CSS v.2.0.5
 * Copyright (c) 2017–2026. Readium Foundation. All rights reserved.
 * Use of this source code is governed by a BSD-style license which is detailed in the
 * LICENSE file present in the project repository where this source code is maintained.
 * Core maintainer: Jiminy Panoz <jiminy.panoz@edrlab.org> 
 * Contributors: 
 * Daniel Weck
 * Hadrien Gardeur
 * Innovimax
 * L. Le Meur
 * Mickaël Menu
 * k_taka
 */

@namespace url("http://www.w3.org/1999/xhtml");

@namespace epub url("http://www.idpf.org/2007/ops");

@namespace m url("http://www.w3.org/1998/Math/MathML");

@namespace svg url("http://www.w3.org/2000/svg");

:root{
  --RS__compFontFamily:var(--RS__baseFontFamily);
  --RS__codeFontFamily:var(--RS__monospaceTf);

  --RS__typeScale:1.125;
  --RS__baseFontSize:100%;

  --RS__flowSpacing:1.5rem;
  --RS__paraSpacing:0;
  --RS__paraIndent:1em;

  --RS__linkColor:#0000EE;
  --RS__visitedColor:#551A8B;

  --RS__primaryColor:;
  --RS__secondaryColor:;
}

body{
  font-size:var(--RS__baseFontSize);
  text-align:justify;
}

h1, h2, h3, h4, h5, h6{
  font-family:var(--RS__compFontFamily);
  text-align:right;
}

blockquote, figure, p, pre,
aside, footer, form, hr{
  margin-top:var(--RS__flowSpacing);
  margin-bottom:var(--RS__flowSpacing);
}

p{
  margin-top:var(--RS__paraSpacing);
  margin-bottom:var(--RS__paraSpacing);
  text-indent:var(--RS__paraIndent);
}

h1 + p, h2 + p, h3 + p, h4 + p, h5 + p, h6 + p,
hr + p{
  text-indent:0;
}

pre{
  font-family:var(--RS__codeFontFamily);
}

code, kbd, samp, tt{
  font-family:var(--RS__codeFontFamily);
}

sub, sup{
  position:relative;
  font-size:67.5%;
  line-height:1;
}

sub{
  bottom:-0.2ex;
}

sup{
  bottom:0;
}

:link{
  color:var(--RS__linkColor);
}

:visited{
  color:var(--RS__visitedColor);
}

h1{
  margin-top:calc(var(--RS__flowSpacing) * 2);
  margin-bottom:calc(var(--RS__flowSpacing) * 2);
  font-size:calc(((1em * var(--RS__typeScale)) * var(--RS__typeScale)) * var(--RS__typeScale));
}

h2{
  margin-top:calc(var(--RS__flowSpacing) * 2);
  margin-bottom:var(--RS__flowSpacing);
  font-size:calc((1em * var(--RS__typeScale)) * var(--RS__typeScale));
}

h3{
  margin-top:var(--RS__flowSpacing);
  margin-bottom:var(--RS__flowSpacing);
  font-size:calc(1em * var(--RS__typeScale));
}

h4{
  margin-top:var(--RS__flowSpacing);
  margin-bottom:var(--RS__flowSpacing);
  font-size:1em;
}

h5{
  margin-top:var(--RS__flowSpacing);
  margin-bottom:var(--RS__flowSpacing);
  font-size:smaller;
}

h6{
  margin-top:var(--RS__flowSpacing);
  margin-bottom:0;
  font-size:smaller;
  font-weight:normal;
}

dl, ol, ul{
  margin-top:var(--RS__flowSpacing);
  margin-bottom:var(--RS__flowSpacing);
}

table{
  margin:var(--RS__flowSpacing) 0;
  border:1px solid currentcolor;
  border-collapse:collapse;
  empty-cells:show;
}

thead, tbody, tfoot, table > tr{
  vertical-align:top;
}

th{
  text-align:initial;
}

th, td{
  padding:4px;
  border:1px solid currentcolor;
}`})),ud=r({default:()=>dd}),dd,fd=n((()=>{dd=`/*!
 * Readium CSS v.2.0.5
 * Copyright (c) 2017–2026. Readium Foundation. All rights reserved.
 * Use of this source code is governed by a BSD-style license which is detailed in the
 * LICENSE file present in the project repository where this source code is maintained.
 * Core maintainer: Jiminy Panoz <jiminy.panoz@edrlab.org> 
 * Contributors: 
 * Daniel Weck
 * Hadrien Gardeur
 * Innovimax
 * L. Le Meur
 * Mickaël Menu
 * k_taka
 */

@namespace url("http://www.w3.org/1999/xhtml");

@namespace epub url("http://www.idpf.org/2007/ops");

@namespace m url("http://www.w3.org/1998/Math/MathML");

@namespace svg url("http://www.w3.org/2000/svg");

:root{

  --RS__viewportWidth:100%;

  --RS__pageGutter:0;

  --RS__defaultLineLength:100%;

  --RS__colGap:0;

  --RS__colCount:1;

  --RS__colWidth:100vw;
}

@page{
  margin:0 !important;
}

:root{
  position:relative;

  -webkit-column-width:var(--RS__colWidth);
  -moz-column-width:var(--RS__colWidth);
  column-width:var(--RS__colWidth);
  -webkit-column-count:var(--RS__colCount);
  -moz-column-count:var(--RS__colCount);
  column-count:var(--RS__colCount);

  -webkit-column-gap:var(--RS__colGap);
  -moz-column-gap:var(--RS__colGap);
  column-gap:var(--RS__colGap);
  -moz-column-fill:auto;
  column-fill:auto;
  width:var(--RS__viewportWidth);
  height:100vh;
  max-width:var(--RS__viewportWidth);
  max-height:100vh;
  min-width:var(--RS__viewportWidth);
  min-height:100vh;
  padding:0 !important;
  margin:0 !important;
  font-size:1rem !important;
  box-sizing:border-box;
  -webkit-touch-callout:none;
}

body{
  width:100%;
  max-width:var(--RS__defaultLineLength) !important;
  margin:0 auto !important;
  box-sizing:border-box;
}

:root:not([style*="readium-scroll-on"]) body{
  padding:0 var(--RS__pageGutter) !important;
}

:root:not([style*="readium-noOverflow-on"]) body{
  overflow:hidden;
}

@supports (overflow: clip){

   :root:not([style*="readium-noOverflow-on"]){
      overflow:clip;
   }

   :root:not([style*="readium-noOverflow-on"]) body{
      overflow:clip;
      overflow-clip-margin:content-box;
   }
}

:root[style*="readium-scroll-on"]{
  -webkit-columns:auto auto !important;
  -moz-columns:auto auto !important;
  columns:auto auto !important;
  width:auto !important;
  height:auto !important;
  max-width:none !important;
  max-height:none !important;
  min-width:0 !important;
  min-height:0 !important;
}

:root[style*="readium-scroll-on"] body{
  max-width:var(--RS__defaultLineLength) !important;
  box-sizing:border-box !important;
}

:root[style*="readium-scroll-on"]:not([style*="readium-noOverflow-on"]) body{
  overflow:auto;
}

@supports (overflow: clip){

  :root[style*="readium-scroll-on"]:not([style*="readium-noOverflow-on"]){
     overflow:auto;
  }

  :root[style*="readium-scroll-on"]:not([style*="readium-noOverflow-on"]) body{
     overflow:clip;
  }
}

:root[style*="readium-scroll-on"][style*="--RS__scrollPaddingTop"] body{
  padding-top:var(--RS__scrollPaddingTop) !important;
}

:root[style*="readium-scroll-on"][style*="--RS__scrollPaddingBottom"] body{
  padding-bottom:var(--RS__scrollPaddingBottom) !important;
}

:root[style*="readium-scroll-on"][style*="--RS__scrollPaddingLeft"] body{
  padding-left:var(--RS__scrollPaddingLeft) !important;
}

:root[style*="readium-scroll-on"][style*="--RS__scrollPaddingRight"] body{
  padding-right:var(--RS__scrollPaddingRight) !important;
}

:root[style*="--USER__backgroundColor"]{
  background-color:var(--USER__backgroundColor) !important;
}

:root[style*="--USER__backgroundColor"] *{
  background-color:transparent !important;
}

:root[style*="--USER__textColor"]{
  color:var(--USER__textColor) !important;
}

:root[style*="--USER__textColor"] *:not(a){
  color:inherit !important;
  background-color:transparent !important;
  border-color:currentcolor !important;
}

:root[style*="--USER__textColor"] svg text{
  fill:currentcolor !important;
  stroke:none !important;
}

:root[style*="--USER__linkColor"] a:link,
:root[style*="--USER__linkColor"] a:link *{
  color:var(--USER__linkColor) !important;
}

:root[style*="--USER__visitedColor"] a:visited,
:root[style*="--USER__visitedColor"] a:visited *{
  color:var(--USER__visitedColor) !important;
}

:root[style*="--USER__selectionBackgroundColor"][style*="--USER__selectionTextColor"] ::-moz-selection{
  color:var(--USER__selectionTextColor) !important;
  background-color:var(--USER__selectionBackgroundColor) !important;
}

:root[style*="--USER__selectionBackgroundColor"][style*="--USER__selectionTextColor"] ::selection{
  color:var(--USER__selectionTextColor) !important;
  background-color:var(--USER__selectionBackgroundColor) !important;
}

:root[style*="--USER__colCount"]{
  -webkit-column-count:var(--USER__colCount);
  -moz-column-count:var(--USER__colCount);
  column-count:var(--USER__colCount);

  --RS__colWidth:auto;
}

:root[style*="--USER__colCount: 0"],
:root[style*="--USER__colCount:0"]{
  -webkit-column-count:1;
  -moz-column-count:1;
  column-count:1;
}

:root[style*="--USER__colCount: 0"],
:root[style*="--USER__colCount:0"],
:root[style*="--USER__colCount: 1"],
:root[style*="--USER__colCount:1"]{
  --RS__colWidth:100vw;
}

:root[style*="--USER__lineLength"] body{
    max-width:var(--USER__lineLength) !important;
  }

:root[style*="--USER__textAlign"]{
  text-align:var(--USER__textAlign);
}

:root[style*="--USER__textAlign"] body,
:root[style*="--USER__textAlign"] p:not(
  blockquote p,
  figcaption p,
  header p,
  hgroup p,
  :root[style*="readium-experimentalHeaderFiltering-on"] p[class*="title"],
  :root[style*="readium-experimentalHeaderFiltering-on"] div:has(+ *) > h1 + p,
  :root[style*="readium-experimentalHeaderFiltering-on"] div:has(+ *) > p:has(+ h1)
),
:root[style*="--USER__textAlign"] li,
:root[style*="--USER__textAlign"] dd{
  text-align:var(--USER__textAlign) !important;
  -moz-text-align-last:auto !important;
  -epub-text-align-last:auto !important;
  text-align-last:auto !important;
}

:root[style*="--USER__fontFamily"]{
  font-family:var(--USER__fontFamily) !important;
}

:root[style*="--USER__fontFamily"] *{
  font-family:revert !important;
}

:root:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] body{
  zoom:var(--USER__fontSize) !important;
}

:root:not([style*="readium-deprecatedFontSize-on"])[style*="readium-iOSPatch-on"][style*="--USER__fontSize"] body{
  -webkit-text-size-adjust:var(--USER__fontSize) !important;
}

@supports selector(figure:has(> img)){

  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] figure:has(> img),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] figure:has(> video),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] figure:has(> svg),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] figure:has(> canvas),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] figure:has(> iframe),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] figure:has(> audio),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] div:has(> img:only-child),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] div:has(> video:only-child),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] div:has(> svg:only-child),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] div:has(> canvas:only-child),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] div:has(> iframe:only-child),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] div:has(> audio:only-child),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] table{
    zoom:calc(100% / var(--USER__fontSize)) !important;
  }

  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] figcaption,
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] caption,
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] td,
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] th{
    zoom:var(--USER__fontSize) !important;
  }
}

@supports not (zoom: 1){

  :root[style*="--USER__fontSize"]{
    font-size:var(--USER__fontSize) !important;
  }
}

:root[style*="readium-deprecatedFontSize-on"][style*="--USER__fontSize"]{
  font-size:var(--USER__fontSize) !important;
}

:root[style*="--USER__lineHeight"]{
  line-height:var(--USER__lineHeight) !important;
}

:root[style*="--USER__lineHeight"] body,
:root[style*="--USER__lineHeight"] p,
:root[style*="--USER__lineHeight"] li,
:root[style*="--USER__lineHeight"] div{
  line-height:var(--USER__lineHeight) !important;
}

:root[style*="--USER__paraSpacing"] p{
  margin-top:var(--USER__paraSpacing) !important;
  margin-bottom:var(--USER__paraSpacing) !important;
}

:root[style*="--USER__paraIndent"] p:not(
  blockquote p,
  figcaption p,
  header p,
  hgroup p,
  :root[style*="readium-experimentalHeaderFiltering-on"] p[class*="title"],
  :root[style*="readium-experimentalHeaderFiltering-on"] div:has(+ *) > h1 + p,
  :root[style*="readium-experimentalHeaderFiltering-on"] div:has(+ *) > p:has(+ h1)
){
  text-indent:var(--USER__paraIndent) !important;
}

:root[style*="--USER__paraIndent"] p *{
  text-indent:0 !important;
}

:root[style*="--USER__wordSpacing"] h1,
:root[style*="--USER__wordSpacing"] h2,
:root[style*="--USER__wordSpacing"] h3,
:root[style*="--USER__wordSpacing"] h4,
:root[style*="--USER__wordSpacing"] h5,
:root[style*="--USER__wordSpacing"] h6,
:root[style*="--USER__wordSpacing"] p,
:root[style*="--USER__wordSpacing"] li,
:root[style*="--USER__wordSpacing"] div,
:root[style*="--USER__wordSpacing"] dt,
:root[style*="--USER__wordSpacing"] dd{
  word-spacing:var(--USER__wordSpacing) !important;
}

:root[style*="--USER__ligatures"]{
  font-variant-ligatures:var(--USER__ligatures) !important;
}

:root[style*="--USER__ligatures"] *{
  font-variant-ligatures:inherit !important;
}

:root[style*="--USER__fontWeight"] body{
  font-weight:var(--USER__fontWeight) !important;
}

:root[style*="--USER__fontWeight"] b,
:root[style*="--USER__fontWeight"] strong{
  font-weight:bolder;
}

:root[style*="--USER__fontWidth"] body{
  font-stretch:var(--USER__fontWidth) !important;
}

:root[style*="--USER__fontOpticalSizing"] body{
  font-optical-sizing:var(--USER__fontOpticalSizing) !important;
}

:root[style*="readium-blend-on"] svg,
:root[style*="readium-blend-on"] img{
  background-color:transparent !important;
  mix-blend-mode:multiply !important;
}

:root[style*="--USER__darkenImages"] img{
  -webkit-filter:brightness(var(--USER__darkenImages)) !important;
  filter:brightness(var(--USER__darkenImages)) !important;
}

:root[style*="readium-darken-on"] img{
  -webkit-filter:brightness(80%) !important;
  filter:brightness(80%) !important;
}

:root[style*="--USER__invertImages"] img{
  -webkit-filter:invert(var(--USER__invertImages)) !important;
  filter:invert(var(--USER__invertImages)) !important;
}

:root[style*="readium-invert-on"] img{
  -webkit-filter:invert(100%) !important;
  filter:invert(100%) !important;
}

:root[style*="--USER__darkenImages"][style*="--USER__invertImages"] img{
  -webkit-filter:brightness(var(--USER__darkenImages)) invert(var(--USER__invertImages)) !important;
  filter:brightness(var(--USER__darkenImages)) invert(var(--USER__invertImages)) !important;
}

:root[style*="readium-darken-on"][style*="--USER__invertImages"] img{
  -webkit-filter:brightness(80%) invert(var(--USER__invertImages)) !important;
  filter:brightness(80%) invert(var(--USER__invertImages)) !important;
}

:root[style*="--USER__darkenImages"][style*="readium-invert-on"] img{
  -webkit-filter:brightness(var(--USER__darkenImages)) invert(100%) !important;
  filter:brightness(var(--USER__darkenImages)) invert(100%) !important;
}

:root[style*="readium-darken-on"][style*="readium-invert-on"] img{
  -webkit-filter:brightness(80%) invert(100%) !important;
  filter:brightness(80%) invert(100%) !important;
}

:root[style*="--USER__invertGaiji"] img[class*="gaiji"]{
  -webkit-filter:invert(var(--USER__invertGaiji)) !important;
  filter:invert(var(--USER__invertGaiji)) !important;
}

:root[style*="readium-invertGaiji-on"] img[class*="gaiji"]{
  -webkit-filter:invert(100%) !important;
  filter:invert(100%) !important;
}

:root[style*="readium-normalize-on"]{
  --USER__typeScale:1.2;
}

:root[style*="readium-normalize-on"] p,
:root[style*="readium-normalize-on"] li,
:root[style*="readium-normalize-on"] div,
:root[style*="readium-normalize-on"] pre,
:root[style*="readium-normalize-on"] dd{
  font-size:1rem !important;
}

:root[style*="readium-normalize-on"] h1{
  font-size:1.75rem !important;
  font-size:calc(((1rem * var(--USER__typeScale)) * var(--USER__typeScale)) * var(--USER__typeScale)) !important;
}

:root[style*="readium-normalize-on"] h2{
  font-size:1.5rem !important;
  font-size:calc((1rem * var(--USER__typeScale)) * var(--USER__typeScale)) !important;
}

:root[style*="readium-normalize-on"] h3{
  font-size:1.25rem !important;
  font-size:calc(1rem * var(--USER__typeScale)) !important;
}

:root[style*="readium-normalize-on"] h4,
:root[style*="readium-normalize-on"] h5,
:root[style*="readium-normalize-on"] h6{
  font-size:1rem !important;
}

:root[style*="readium-normalize-on"] small{
  font-size:smaller !important;
}

:root[style*="readium-normalize-on"] sub,
:root[style*="readium-normalize-on"] sup{
  font-size:67.5% !important;
}

:root[style*="readium-normalize-on"][style*="--USER__typeScale"] h1{
  font-size:calc(((1rem * var(--USER__typeScale)) * var(--USER__typeScale)) * var(--USER__typeScale)) !important;
}

:root[style*="readium-normalize-on"][style*="--USER__typeScale"] h2{
  font-size:calc((1rem * var(--USER__typeScale)) * var(--USER__typeScale)) !important;
}

:root[style*="readium-normalize-on"][style*="--USER__typeScale"] h3{
  font-size:calc(1rem * var(--USER__typeScale)) !important;
}

:root[style*="readium-iPadOSPatch-on"] body{
  -webkit-text-size-adjust:none;
}

:root[style*="readium-iPadOSPatch-on"] p, 
:root[style*="readium-iPadOSPatch-on"] h1, 
:root[style*="readium-iPadOSPatch-on"] h2, 
:root[style*="readium-iPadOSPatch-on"] h3, 
:root[style*="readium-iPadOSPatch-on"] h4, 
:root[style*="readium-iPadOSPatch-on"] h5, 
:root[style*="readium-iPadOSPatch-on"] h6, 
:root[style*="readium-iPadOSPatch-on"] li, 
:root[style*="readium-iPadOSPatch-on"] th, 
:root[style*="readium-iPadOSPatch-on"] td, 
:root[style*="readium-iPadOSPatch-on"] dt, 
:root[style*="readium-iPadOSPatch-on"] dd, 
:root[style*="readium-iPadOSPatch-on"] pre, 
:root[style*="readium-iPadOSPatch-on"] address, 
:root[style*="readium-iPadOSPatch-on"] details, 
:root[style*="readium-iPadOSPatch-on"] summary,
:root[style*="readium-iPadOSPatch-on"] figcaption,
:root[style*="readium-iPadOSPatch-on"] div:not(:has(p, h1, h2, h3, h4, h5, h6, li, th, td, dt, dd, pre, address, aside, details, figcaption, summary)),
:root[style*="readium-iPadOSPatch-on"] aside:not(:has(p, h1, h2, h3, h4, h5, h6, li, th, td, dt, dd, pre, address, aside, details, figcaption, summary)){
  -webkit-text-zoom:reset;
}

:root[style*="readium-iPadOSPatch-on"] abbr, 
:root[style*="readium-iPadOSPatch-on"] b, 
:root[style*="readium-iPadOSPatch-on"] bdi, 
:root[style*="readium-iPadOSPatch-on"] bdo, 
:root[style*="readium-iPadOSPatch-on"] cite, 
:root[style*="readium-iPadOSPatch-on"] code, 
:root[style*="readium-iPadOSPatch-on"] dfn, 
:root[style*="readium-iPadOSPatch-on"] em, 
:root[style*="readium-iPadOSPatch-on"] i, 
:root[style*="readium-iPadOSPatch-on"] kbd, 
:root[style*="readium-iPadOSPatch-on"] mark, 
:root[style*="readium-iPadOSPatch-on"] q, 
:root[style*="readium-iPadOSPatch-on"] rp, 
:root[style*="readium-iPadOSPatch-on"] rt, 
:root[style*="readium-iPadOSPatch-on"] ruby, 
:root[style*="readium-iPadOSPatch-on"] s, 
:root[style*="readium-iPadOSPatch-on"] samp, 
:root[style*="readium-iPadOSPatch-on"] small, 
:root[style*="readium-iPadOSPatch-on"] span, 
:root[style*="readium-iPadOSPatch-on"] strong, 
:root[style*="readium-iPadOSPatch-on"] sub, 
:root[style*="readium-iPadOSPatch-on"] sup, 
:root[style*="readium-iPadOSPatch-on"] time, 
:root[style*="readium-iPadOSPatch-on"] u, 
:root[style*="readium-iPadOSPatch-on"] var{
  -webkit-text-zoom:normal;
}

:root[style*="readium-iPadOSPatch-on"] p:not(:has(b, cite, em, i, q, s, small, span, strong)):first-line{
  -webkit-text-zoom:normal;
}`})),pd=r({default:()=>md}),md,hd=n((()=>{md=`/*!
 * Readium CSS v.2.0.5
 * Copyright (c) 2017–2026. Readium Foundation. All rights reserved.
 * Use of this source code is governed by a BSD-style license which is detailed in the
 * LICENSE file present in the project repository where this source code is maintained.
 * Core maintainer: Jiminy Panoz <jiminy.panoz@edrlab.org> 
 * Contributors: 
 * Daniel Weck
 * Hadrien Gardeur
 * Innovimax
 * L. Le Meur
 * Mickaël Menu
 * k_taka
 */

@namespace url("http://www.w3.org/1999/xhtml");

@namespace epub url("http://www.idpf.org/2007/ops");

@namespace m url("http://www.w3.org/1998/Math/MathML");

@namespace svg url("http://www.w3.org/2000/svg");

@-ms-viewport{
  width:device-width;
}

@viewport{
  width:device-width;
  zoom:1;
}

:root{

  --RS__sans-serif-ja-v:'Hiragino Sans', 'Hiragino Kaku Gothic ProN', 'Hiragino Kaku Gothic Pro', 'ヒラギノ角ゴ W3', 'YuGothic', 'Yu Gothic Medium', 'BIZ UDGothic', 'Yu Gothic', 'ＭＳゴシック', 'MS Gothic', sans-serif;

  --RS__serif-ja-v:'Hiragino Mincho ProN', 'Hiragino Mincho Pro', 'YuMincho', 'BIZ UDMincho', 'Yu Mincho', 'ＭＳ明朝', 'MS Mincho', serif;

  --RS__sans-serif-ja:'Hiragino Sans', 'Hiragino Kaku Gothic ProN', 'Hiragino Kaku Gothic Pro', 'ヒラギノ角ゴ W3', 'YuGothic', 'Yu Gothic Medium', 'BIZ UDPGothic', 'Yu Gothic', 'ＭＳ Ｐゴシック', 'MS PGothic', sans-serif;

  --RS__serif-ja:'Hiragino Mincho ProN', 'Hiragino Mincho Pro', 'YuMincho', 'BIZ UDPMincho', 'Yu Mincho', 'ＭＳ Ｐ明朝', 'MS PMincho', serif;

  --RS__monospaceTf:ui-monospace, 'Andale Mono', 'Cascadia Code', 'Source Code Pro', Menlo, Consolas, 'DejaVu Sans Mono', monospace;

  --RS__humanistTf:Seravek, Calibri, 'Gill Sans Nova', Roboto, Ubuntu, 'DejaVu Sans', source-sans-pro, sans-serif;

  --RS__sansTf:-ui-sans-serif, -apple-system, system-ui, BlinkMacSystemFont, 'Segoe UI Variable', 'Segoe UI', Inter, Roboto, 'Helvetica Neue', 'Arial Nova', 'Liberation Sans', Arial, sans-serif;

  --RS__modernTf:Athelas, Constantia, Charter, 'Bitstream Charter', Cambria, 'Georgia Pro', Georgia, serif;

  --RS__oldStyleTf:'Iowan Old Style', Sitka, 'Sitka Text', Palatino, 'Book Antiqua', 'URW Palladio L', P052, serif;

  --RS__zh-HK-lineHeightCompensation:1.167;

  --RS__zh-HK-baseFontFamily:'方體', 'PingFang HK', '方體', 'PingFang TC', '黑體', 'Heiti TC', 'Microsoft JhengHei UI', 'Microsoft JhengHei', Roboto, Noto, 'Noto Sans CJK TC', sans-serif;

  --RS__zh-TW-lineHeightCompensation:1.167;

  --RS__zh-TW-baseFontFamily:'方體', 'PingFang TC', '黑體', 'Heiti TC', 'Microsoft JhengHei UI', 'Microsoft JhengHei', Roboto, Noto, 'Noto Sans CJK TC', sans-serif;

  --RS__zh-Hant-lineHeightCompensation:1.167;

  --RS__zh-Hant-baseFontFamily:'方體', 'PingFang TC', '黑體', 'Heiti TC', 'Microsoft JhengHei UI', 'Microsoft JhengHei', Roboto, Noto, 'Noto Sans CJK TC', sans-serif;

  --RS__zh-lineHeightCompensation:1.167;

  --RS__zh-baseFontFamily:'方体', 'PingFang SC', '黑体', 'Heiti SC', 'Microsoft JhengHei UI', 'Microsoft JhengHei', Roboto, Noto, 'Noto Sans CJK SC', sans-serif;

  --RS__th-lineHeightCompensation:1.067;

  --RS__th-baseFontFamily:Thonburi, 'Leelawadee UI', 'Cordia New', Roboto, Noto, 'Noto Sans Thai', sans-serif;

  --RS__te-baseFontFamily:'Kohinoor Telugu', 'Telugu Sangam MN', 'Nirmala UI', Gautami, Roboto, Noto, 'Noto Sans Telugu', sans-serif;

  --RS__ta-lineHeightCompensation:1.067;

  --RS__ta-baseFontFamily:'Tamil Sangam MN', 'Nirmala UI', Latha, Roboto, Noto, 'Noto Sans Tamil', sans-serif;

  --RS__si-lineHeightCompensation:1.167;

  --RS__si-baseFontFamily:'Sinhala Sangam MN', 'Nirmala UI', 'Iskoola Pota', Roboto, Noto, 'Noto Sans Sinhala', sans-serif;

  --RS__pa-lineHeightCompensation:1.1;

  --RS__pa-baseFontFamily:'Gurmukhi MN', 'Nirmala UI', Kartika, Roboto, Noto, 'Noto Sans Gurmukhi', sans-serif;

  --RS__or-lineHeightCompensation:1.167;

  --RS__or-baseFontFamily:'Oriya Sangam MN', 'Nirmala UI', Kalinga, Roboto, Noto, 'Noto Sans Oriya', sans-serif;

  --RS__ml-lineHeightCompensation:1.067;

  --RS__ml-baseFontFamily:'Malayalam Sangam MN', 'Nirmala UI', Kartika, Roboto, Noto, 'Noto Sans Malayalam', sans-serif;

  --RS__lo-baseFontFamily:'Lao Sangam MN', 'Leelawadee UI', 'Lao UI', Roboto, Noto, 'Noto Sans Lao', sans-serif;

  --RS__ko-lineHeightCompensation:1.167;

  --RS__ko-baseFontFamily:'Nanum Gothic', 'Apple SD Gothic Neo', 'Malgun Gothic', Roboto, Noto, 'Noto Sans CJK KR', sans-serif;

  --RS__kn-lineHeightCompensation:1.1;

  --RS__kn-baseFontFamily:'Kannada Sangam MN', 'Nirmala UI', Tunga, Roboto, Noto, 'Noto Sans Kannada', sans-serif;

  --RS__km-lineHeightCompensation:1.067;

  --RS__km-baseFontFamily:'Khmer Sangam MN', 'Leelawadee UI', 'Khmer UI', Roboto, Noto, 'Noto Sans Khmer', sans-serif;

  --RS__ja-lineHeightCompensation:1.167;

  --RS__ja-baseFontFamily:YuGothic, 'Hiragino Maru Gothic ProN', 'Hiragino Sans', 'Yu Gothic UI', 'Meiryo UI', 'MS Gothic', Roboto, Noto, 'Noto Sans CJK JP', sans-serif;

  --RS__iu-baseFontFamily:'Euphemia UCAS', Euphemia, Roboto, Noto, 'Noto Sans Canadian Aboriginal', sans-serif;

  --RS__hy-baseFontFamily:Mshtakan, Sylfaen, Roboto, Noto, 'Noto Serif Armenian', serif;

  --RS__hi-lineHeightCompensation:1.1;

  --RS__hi-baseFontFamily:'Kohinoor Devanagari', 'Devanagari Sangam MN', Kokila, 'Nirmala UI', Roboto, Noto, 'Noto Sans Devanagari', sans-serif;

  --RS__he-lineHeightCompensation:1.1;

  --RS__he-baseFontFamily:'New Peninim MT', 'Arial Hebrew', Gisha, 'Times New Roman', Roboto, Noto, 'Noto Sans Hebrew', sans-serif;

  --RS__gu-lineHeightCompensation:1.167;

  --RS__gu-baseFontFamily:'Gujarati Sangam MN', 'Nirmala UI', Shruti, Roboto, Noto, 'Noto Sans Gujarati', sans-serif;

  --RS__fa-baseFontFamily:'Geeza Pro', 'Arabic Typesetting', Roboto, Noto, 'Noto Naskh Arabic', 'Times New Roman', serif;

  --RS__chr-lineHeightCompensation:1.167;

  --RS__chr-baseFontFamily:'Plantagenet Cherokee', Roboto, Noto, 'Noto Sans Cherokee';

  --RS__bo-baseFontFamily:Kailasa, 'Microsoft Himalaya', Roboto, Noto, 'Noto Sans Tibetan', sans-serif;

  --RS__bn-lineHeightCompensation:1.067;

  --RS__bn-baseFontFamily:'Kohinoor Bangla', 'Bangla Sangam MN', Vrinda, Roboto, Noto, 'Noto Sans Bengali', sans-serif;

  --RS__ar-baseFontFamily:'Geeza Pro', 'Arabic Typesetting', Roboto, Noto, 'Noto Naskh Arabic', 'Times New Roman', serif;

  --RS__am-lineHeightCompensation:1.167;

  --RS__am-baseFontFamily:Kefa, Nyala, Roboto, Noto, 'Noto Sans Ethiopic', serif;

  --RS__latin-lineHeightCompensation:1;

  --RS__latin-baseFontFamily:var(--RS__oldStyleTf);
  --RS__baseFontFamily:var(--RS__latin-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__latin-lineHeightCompensation);
  --RS__baseLineHeight:calc(1.5 * var(--RS__lineHeightCompensation));

  --RS__selectionTextColor:inherit;

  --RS__selectionBackgroundColor:#b4d8fe;

  --RS__visitedColor:#551A8B;

  --RS__linkColor:#0000EE;

  --RS__textColor:#121212;

  --RS__backgroundColor:#FFFFFF;
  color:var(--RS__textColor) !important;

  background-color:var(--RS__backgroundColor) !important;
}

::-moz-selection{
  color:var(--RS__selectionTextColor);
  background-color:var(--RS__selectionBackgroundColor);
}

::selection{
  color:var(--RS__selectionTextColor);
  background-color:var(--RS__selectionBackgroundColor);
}

html{
  font-family:var(--RS__baseFontFamily);
  line-height:1.6;
  line-height:var(--RS__baseLineHeight);
  text-rendering:optimizelegibility;
}

h1, h2, h3{
  line-height:normal;
}

:lang(ja),
:lang(zh),
:lang(ko){
  word-wrap:break-word;
  -webkit-line-break:strict;
  -epub-line-break:strict;
  line-break:strict;
}

math{
  font-family:"Latin Modern Math", "STIX Two Math", "XITS Math", "STIX Math", "Libertinus Math", "TeX Gyre Termes Math", "TeX Gyre Bonum Math", "TeX Gyre Schola", "DejaVu Math TeX Gyre", "TeX Gyre Pagella Math", "Asana Math", "Cambria Math", "Lucida Bright Math", "Minion Math", STIXGeneral, STIXSizeOneSym, Symbol, "Times New Roman", serif;
}

:lang(am){
  --RS__baseFontFamily:var(--RS__am-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__am-lineHeightCompensation);
}

:lang(ar){
  --RS__baseFontFamily:var(--RS__ar-baseFontFamily);
}

:lang(bn){
  --RS__baseFontFamily:var(--RS__bn-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__bn-lineHeightCompensation);
}

:lang(bo){
  --RS__baseFontFamily:var(--RS__bo-baseFontFamily);
}

:lang(chr){
  --RS__baseFontFamily:var(--RS__chr-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__chr-lineHeightCompensation);
}

:lang(fa){
  --RS__baseFontFamily:var(--RS__fa-baseFontFamily);
}

:lang(gu){
  --RS__baseFontFamily:var(--RS__gu-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__gu-lineHeightCompensation);
}

:lang(he){
  --RS__baseFontFamily:var(--RS__he-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__he-lineHeightCompensation);
}

:lang(hi){
  --RS__baseFontFamily:var(--RS__hi-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__hi-lineHeightCompensation);
}

:lang(hy){
  --RS__baseFontFamily:var(--RS__hy-baseFontFamily);
}

:lang(iu){
  --RS__baseFontFamily:var(--RS__iu-baseFontFamily);
}

:lang(ja){
  --RS__baseFontFamily:var(--RS__ja-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__ja-lineHeightCompensation);
}

:lang(km){
  --RS__baseFontFamily:var(--RS__km-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__km-lineHeightCompensation);
}

:lang(kn){
  --RS__baseFontFamily:var(--RS__kn-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__kn-lineHeightCompensation);
}

:lang(ko){
  --RS__baseFontFamily:var(--RS__ko-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__ko-lineHeightCompensation);
}

:lang(lo){
  --RS__baseFontFamily:var(--RS__lo-baseFontFamily);
}

:lang(ml){
  --RS__baseFontFamily:var(--RS__ml-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__ml-lineHeightCompensation);
}

:lang(or){
  --RS__baseFontFamily:var(--RS__or-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__or-lineHeightCompensation);
}

:lang(pa){
  --RS__baseFontFamily:var(--RS__pa-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__pa-lineHeightCompensation);
}

:lang(si){
  --RS__baseFontFamily:var(--RS__si-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__si-lineHeightCompensation);
}

:lang(ta){
  --RS__baseFontFamily:var(--RS__ta-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__ta-lineHeightCompensation);
}

:lang(te){
  --RS__baseFontFamily:var(--RS__te-baseFontFamily);
}

:lang(th){
  --RS__baseFontFamily:var(--RS__th-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__th-lineHeightCompensation);
}

:lang(zh){
  --RS__baseFontFamily:var(--RS__zh-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__zh-lineHeightCompensation);
}

:lang(zh-Hant){
  --RS__baseFontFamily:var(--RS__zh-Hant-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__zh-Hant-lineHeightCompensation);
}

:lang(zh-TW){
  --RS__baseFontFamily:var(--RS__zh-TW-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__zh-TW-lineHeightCompensation);
}

:lang(zh-HK){
  --RS__baseFontFamily:var(--RS__zh-HK-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__zh-HK-lineHeightCompensation);
}

body{
  widows:2;
  orphans:2;
}

figcaption, th, td{
  widows:1;
  orphans:1;
}

h2, h3, h4, h5, h6, dt,
hr, caption{
  -webkit-column-break-after:avoid;
  page-break-after:avoid;
  break-after:avoid;
}

h1, h2, h3, h4, h5, h6, dt,
figure, tr{
  -webkit-column-break-inside:avoid;
  page-break-inside:avoid;
  break-inside:avoid;
}

body{
  -webkit-hyphenate-character:"\\002D";
  -moz-hyphenate-character:"\\002D";
  -ms-hyphenate-character:"\\002D";
  hyphenate-character:"\\002D";
  -webkit-hyphenate-limit-lines:3;
  -ms-hyphenate-limit-lines:3;
  hyphenate-limit-lines:3;
}

h1, h2, h3, h4, h5, h6, dt,
figcaption, pre, caption, address,
center, code, var{
  -ms-hyphens:none;
  -moz-hyphens:none;
  -webkit-hyphens:none;
  -epub-hyphens:none;
  hyphens:none;
}

body{
  font-variant-numeric:oldstyle-nums proportional-nums;
}

:lang(ja) body,
:lang(zh) body,
:lang(ko) body{
  font-variant-numeric:lining-nums proportional-nums;
}

h1, h2, h3, h4, h5, h6, dt{
  font-variant-numeric:lining-nums proportional-nums;
}

table{
  font-variant-numeric:lining-nums tabular-nums;
}

code, var{
  font-variant-ligatures:none;
  font-variant-numeric:lining-nums tabular-nums slashed-zero;
}

rt{
  font-variant-east-asian:ruby;
}

:lang(ar){
  font-variant-ligatures:common-ligatures;
}

:lang(ko){
  font-kerning:normal;
}

hr{
  color:inherit;
  border-color:currentcolor;
}

table, th, td{
  border-color:currentcolor;
}

figure, blockquote{
  margin:1em 5%;
}

ul, ol{
  padding-left:5%;
}

dd{
  margin-left:5%;
}

pre{
  white-space:pre-wrap;
  -ms-tab-size:2;
  -moz-tab-size:2;
  -webkit-tab-size:2;
  tab-size:2;
}

abbr[title], acronym[title]{
  text-decoration:dotted underline;
}

nobr wbr{
  white-space:normal;
}

ruby > rt, ruby > rp{
  -webkit-user-select:none;
  -moz-user-select:none;
  -ms-user-select:none;
  user-select:none;
}

*:lang(ja):not(:lang(ja-Latn)):not(:lang(ja-Cyrl)),
*:lang(zh):not(:lang(zh-Latn)):not(:lang(zh-Cyrl)),
*:lang(ko):not(:lang(ko-Latn)):not(:lang(ko-Cyrl)),
:lang(ja):not(:lang(ja-Latn)):not(:lang(ja-Cyrl)) cite, 
:lang(ja):not(:lang(ja-Latn)):not(:lang(ja-Cyrl)) dfn, 
:lang(ja):not(:lang(ja-Latn)):not(:lang(ja-Cyrl)) em, 
:lang(ja):not(:lang(ja-Latn)):not(:lang(ja-Cyrl)) i,
:lang(zh):not(:lang(zh-Latn)):not(:lang(zh-Cyrl)) cite, 
:lang(zh):not(:lang(zh-Latn)):not(:lang(zh-Cyrl)) dfn, 
:lang(zh):not(:lang(zh-Latn)):not(:lang(zh-Cyrl)) em, 
:lang(zh):not(:lang(zh-Latn)):not(:lang(zh-Cyrl)) i,
:lang(ko):not(:lang(ko-Latn)):not(:lang(ko-Cyrl)) cite, 
:lang(ko):not(:lang(ko-Latn)):not(:lang(ko-Cyrl)) dfn, 
:lang(ko):not(:lang(ko-Latn)):not(:lang(ko-Cyrl)) em, 
:lang(ko):not(:lang(ko-Latn)):not(:lang(ko-Cyrl)) i{
  font-style:normal;
}

:lang(ja) a,
:lang(zh) a,
:lang(ko) a{
  text-decoration:none;
}

:root{
  --RS__maxMediaWidth:100%;
  --RS__maxMediaHeight:95vh;
  --RS__boxSizingMedia:border-box;
  --RS__boxSizingTable:border-box;
}

a, a span, span a, h1, h2, h3, h4, h5, h6{
  word-wrap:break-word;
}

div{
  max-width:var(--RS__maxMediaWidth);
}

img, svg|svg, video{
  object-fit:contain;

  width:auto;
  height:auto;
  max-width:var(--RS__maxMediaWidth);
  max-height:var(--RS__maxMediaHeight) !important;
  box-sizing:var(--RS__boxSizingMedia);
  -webkit-column-break-inside:avoid;
  page-break-inside:avoid;
  break-inside:avoid;
}

@supports (zoom: 1) and (not ((-webkit-column-axis: horizontal) and (-webkit-column-progression: normal))){

  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] img,
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] svg|svg,
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] video{
    zoom:calc(100% / var(--USER__fontSize));
  }
}

audio{
    max-width:100%;
    -webkit-column-break-inside:avoid;
    page-break-inside:avoid;
    break-inside:avoid;
  }

table{
  max-width:var(--RS__maxMediaWidth);
  box-sizing:var(--RS__boxSizingTable);
}`})),gd=r({default:()=>_d}),_d,vd=n((()=>{_d=`/*!
 * Readium CSS v.2.0.5
 * Copyright (c) 2017–2026. Readium Foundation. All rights reserved.
 * Use of this source code is governed by a BSD-style license which is detailed in the
 * LICENSE file present in the project repository where this source code is maintained.
 * Core maintainer: Jiminy Panoz <jiminy.panoz@edrlab.org> 
 * Contributors: 
 * Daniel Weck
 * Hadrien Gardeur
 * Innovimax
 * L. Le Meur
 * Mickaël Menu
 * k_taka
 */

@namespace url("http://www.w3.org/1999/xhtml");

@namespace epub url("http://www.idpf.org/2007/ops");

@namespace m url("http://www.w3.org/1998/Math/MathML");

@namespace svg url("http://www.w3.org/2000/svg");

:root{

  --RS__compFontFamily:var(--RS__baseFontFamily);
  --RS__codeFontFamily:var(--RS__monospaceTf);

  --RS__typeScale:1.125;
  --RS__baseFontSize:87.5%;

  --RS__flowSpacing:1.5rem;
  --RS__paraSpacing:0;
  --RS__paraIndent:1em;

  --RS__linkColor:#0000EE;
  --RS__visitedColor:#551A8B;

  --RS__primaryColor:;
  --RS__secondaryColor:;
}

:root:lang(zh){
  --RS__paraIndent:2em;
}

:root{
  quotes:"\\201c" "\\201d" "\\2018" "\\2019";
}

body{
  font-size:var(--RS__baseFontSize);
  text-align:justify;
  text-justify:inter-character;
}

h1, h2, h3, h4, h5, h6{
  font-family:var(--RS__baseFontFamily);
  text-align:left;
  text-align:start;
}

blockquote, figure, p, pre,
aside, footer, form, hr{
  margin-top:var(--RS__flowSpacing);
  margin-bottom:var(--RS__flowSpacing);
}

p{
  margin-top:var(--RS__paraSpacing);
  margin-bottom:var(--RS__paraSpacing);
  text-indent:var(--RS__paraIndent);
}

pre{
  font-family:var(--RS__codeFontFamily);
}

code, kbd, samp, tt{
  font-family:var(--RS__codeFontFamily);
}

sub, sup{
  position:relative;
  font-size:67.5%;
  line-height:1;
}

sub{
  bottom:-0.2ex;
}

sup{
  bottom:0;
}

em{
  -webkit-text-emphasis:dot;
  -epub-text-emphasis:dot;
  text-emphasis:dot;
}

:link{
  color:var(--RS__linkColor);
}

:visited{
  color:var(--RS__visitedColor);
}

h1{
  margin-top:calc(var(--RS__flowSpacing) * 2);
  margin-bottom:calc(var(--RS__flowSpacing) * 2);
  font-size:calc(((1em * var(--RS__typeScale)) * var(--RS__typeScale)) * var(--RS__typeScale));
  text-align:center;
}

h2{
  margin-top:calc(var(--RS__flowSpacing) * 2);
  margin-bottom:var(--RS__flowSpacing);
  font-size:calc((1em * var(--RS__typeScale)) * var(--RS__typeScale));
  text-align:center;
}

h3{
  margin-top:var(--RS__flowSpacing);
  margin-bottom:var(--RS__flowSpacing);
  font-size:calc(1em * var(--RS__typeScale));
  text-align:center;
}

h4{
  margin-top:var(--RS__flowSpacing);
  margin-bottom:var(--RS__flowSpacing);
  font-family:var(--RS__compFontFamily);
  font-size:1em;
}

h5{
  margin-top:var(--RS__flowSpacing);
  margin-bottom:var(--RS__flowSpacing);
  font-family:var(--RS__compFontFamily);
  font-size:smaller;
}

h6{
  margin-top:var(--RS__flowSpacing);
  margin-bottom:0;
  font-family:var(--RS__compFontFamily);
  font-size:smaller;
  font-weight:normal;
}

dl, ol, ul{
  margin-top:var(--RS__flowSpacing);
  margin-bottom:var(--RS__flowSpacing);
}

table{
  margin:var(--RS__flowSpacing) 0;
  border:1px solid currentcolor;
  border-collapse:collapse;
  empty-cells:show;
}

thead, tbody, tfoot, table > tr{
  vertical-align:top;
}

th{
  text-align:left;
}

th, td{
  padding:4px;
  border:1px solid currentcolor;
}`})),yd=r({default:()=>bd}),bd,xd=n((()=>{bd=`/*!
 * Readium CSS v.2.0.5
 * Copyright (c) 2017–2026. Readium Foundation. All rights reserved.
 * Use of this source code is governed by a BSD-style license which is detailed in the
 * LICENSE file present in the project repository where this source code is maintained.
 * Core maintainer: Jiminy Panoz <jiminy.panoz@edrlab.org> 
 * Contributors: 
 * Daniel Weck
 * Hadrien Gardeur
 * Innovimax
 * L. Le Meur
 * Mickaël Menu
 * k_taka
 */

@namespace url("http://www.w3.org/1999/xhtml");

@namespace epub url("http://www.idpf.org/2007/ops");

@namespace m url("http://www.w3.org/1998/Math/MathML");

@namespace svg url("http://www.w3.org/2000/svg");

:root{

  --RS__viewportWidth:100%;

  --RS__pageGutter:0;

  --RS__defaultLineLength:100%;

  --RS__colGap:0;

  --RS__colCount:1;

  --RS__colWidth:100vw;
}

@page{
  margin:0 !important;
}

:root{
  position:relative;

  -webkit-column-width:var(--RS__colWidth);
  -moz-column-width:var(--RS__colWidth);
  column-width:var(--RS__colWidth);
  -webkit-column-count:var(--RS__colCount);
  -moz-column-count:var(--RS__colCount);
  column-count:var(--RS__colCount);

  -webkit-column-gap:var(--RS__colGap);
  -moz-column-gap:var(--RS__colGap);
  column-gap:var(--RS__colGap);
  -moz-column-fill:auto;
  column-fill:auto;
  width:var(--RS__viewportWidth);
  height:100vh;
  max-width:var(--RS__viewportWidth);
  max-height:100vh;
  min-width:var(--RS__viewportWidth);
  min-height:100vh;
  padding:0 !important;
  margin:0 !important;
  font-size:1rem !important;
  box-sizing:border-box;
  -webkit-touch-callout:none;
}

body{
  width:100%;
  max-width:var(--RS__defaultLineLength) !important;
  margin:0 auto !important;
  box-sizing:border-box;
}

:root:not([style*="readium-scroll-on"]) body{
  padding:0 var(--RS__pageGutter) !important;
}

:root:not([style*="readium-noOverflow-on"]) body{
  overflow:hidden;
}

@supports (overflow: clip){

   :root:not([style*="readium-noOverflow-on"]){
      overflow:clip;
   }

   :root:not([style*="readium-noOverflow-on"]) body{
      overflow:clip;
      overflow-clip-margin:content-box;
   }
}

:root[style*="readium-scroll-on"]{
  -webkit-columns:auto auto !important;
  -moz-columns:auto auto !important;
  columns:auto auto !important;
  width:auto !important;
  height:auto !important;
  max-width:none !important;
  max-height:none !important;
  min-width:0 !important;
  min-height:0 !important;
}

:root[style*="readium-scroll-on"] body{
  max-width:var(--RS__defaultLineLength) !important;
  box-sizing:border-box !important;
}

:root[style*="readium-scroll-on"]:not([style*="readium-noOverflow-on"]) body{
  overflow:auto;
}

@supports (overflow: clip){

  :root[style*="readium-scroll-on"]:not([style*="readium-noOverflow-on"]){
     overflow:auto;
  }

  :root[style*="readium-scroll-on"]:not([style*="readium-noOverflow-on"]) body{
     overflow:clip;
  }
}

:root[style*="readium-scroll-on"][style*="--RS__scrollPaddingTop"] body{
  padding-top:var(--RS__scrollPaddingTop) !important;
}

:root[style*="readium-scroll-on"][style*="--RS__scrollPaddingBottom"] body{
  padding-bottom:var(--RS__scrollPaddingBottom) !important;
}

:root[style*="readium-scroll-on"][style*="--RS__scrollPaddingLeft"] body{
  padding-left:var(--RS__scrollPaddingLeft) !important;
}

:root[style*="readium-scroll-on"][style*="--RS__scrollPaddingRight"] body{
  padding-right:var(--RS__scrollPaddingRight) !important;
}

:root[style*="--USER__backgroundColor"]{
  background-color:var(--USER__backgroundColor) !important;
}

:root[style*="--USER__backgroundColor"] *{
  background-color:transparent !important;
}

:root[style*="--USER__textColor"]{
  color:var(--USER__textColor) !important;
}

:root[style*="--USER__textColor"] *:not(a){
  color:inherit !important;
  background-color:transparent !important;
  border-color:currentcolor !important;
}

:root[style*="--USER__textColor"] svg text{
  fill:currentcolor !important;
  stroke:none !important;
}

:root[style*="--USER__linkColor"] a:link,
:root[style*="--USER__linkColor"] a:link *{
  color:var(--USER__linkColor) !important;
}

:root[style*="--USER__visitedColor"] a:visited,
:root[style*="--USER__visitedColor"] a:visited *{
  color:var(--USER__visitedColor) !important;
}

:root[style*="--USER__selectionBackgroundColor"][style*="--USER__selectionTextColor"] ::-moz-selection{
  color:var(--USER__selectionTextColor) !important;
  background-color:var(--USER__selectionBackgroundColor) !important;
}

:root[style*="--USER__selectionBackgroundColor"][style*="--USER__selectionTextColor"] ::selection{
  color:var(--USER__selectionTextColor) !important;
  background-color:var(--USER__selectionBackgroundColor) !important;
}

:root[style*="--USER__colCount"]{
  -webkit-column-count:var(--USER__colCount);
  -moz-column-count:var(--USER__colCount);
  column-count:var(--USER__colCount);

  --RS__colWidth:auto;
}

:root[style*="--USER__colCount: 0"],
:root[style*="--USER__colCount:0"]{
  -webkit-column-count:1;
  -moz-column-count:1;
  column-count:1;
}

:root[style*="--USER__colCount: 0"],
:root[style*="--USER__colCount:0"],
:root[style*="--USER__colCount: 1"],
:root[style*="--USER__colCount:1"]{
  --RS__colWidth:100vw;
}

:root[style*="--USER__lineLength"] body{
    max-width:var(--USER__lineLength) !important;
  }

:root[style*="--USER__fontFamily"]{
  font-family:var(--USER__fontFamily) !important;
}

:root[style*="--USER__fontFamily"] *{
  font-family:revert !important;
}

:root:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] body{
  zoom:var(--USER__fontSize) !important;
}

:root:not([style*="readium-deprecatedFontSize-on"])[style*="readium-iOSPatch-on"][style*="--USER__fontSize"] body{
  -webkit-text-size-adjust:var(--USER__fontSize) !important;
}

@supports selector(figure:has(> img)){

  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] figure:has(> img),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] figure:has(> video),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] figure:has(> svg),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] figure:has(> canvas),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] figure:has(> iframe),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] figure:has(> audio),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] div:has(> img:only-child),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] div:has(> video:only-child),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] div:has(> svg:only-child),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] div:has(> canvas:only-child),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] div:has(> iframe:only-child),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] div:has(> audio:only-child),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] table{
    zoom:calc(100% / var(--USER__fontSize)) !important;
  }

  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] figcaption,
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] caption,
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] td,
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] th{
    zoom:var(--USER__fontSize) !important;
  }
}

@supports not (zoom: 1){

  :root[style*="--USER__fontSize"]{
    font-size:var(--USER__fontSize) !important;
  }
}

:root[style*="readium-deprecatedFontSize-on"][style*="--USER__fontSize"]{
  font-size:var(--USER__fontSize) !important;
}

:root[style*="--USER__lineHeight"]{
  line-height:var(--USER__lineHeight) !important;
}

:root[style*="--USER__lineHeight"] body,
:root[style*="--USER__lineHeight"] p,
:root[style*="--USER__lineHeight"] li,
:root[style*="--USER__lineHeight"] div{
  line-height:var(--USER__lineHeight) !important;
}

:root[style*="--USER__paraSpacing"] p{
  margin-top:var(--USER__paraSpacing) !important;
  margin-bottom:var(--USER__paraSpacing) !important;
}

:root[style*="--USER__fontWeight"] body{
  font-weight:var(--USER__fontWeight) !important;
}

:root[style*="--USER__fontWeight"] b,
:root[style*="--USER__fontWeight"] strong{
  font-weight:bolder;
}

:root[style*="--USER__fontWidth"] body{
  font-stretch:var(--USER__fontWidth) !important;
}

:root[style*="--USER__fontOpticalSizing"] body{
  font-optical-sizing:var(--USER__fontOpticalSizing) !important;
}

:root[style*="--USER__letterSpacing"] h1,
:root[style*="--USER__letterSpacing"] h2,
:root[style*="--USER__letterSpacing"] h3,
:root[style*="--USER__letterSpacing"] h4,
:root[style*="--USER__letterSpacing"] h5,
:root[style*="--USER__letterSpacing"] h6,
:root[style*="--USER__letterSpacing"] p,
:root[style*="--USER__letterSpacing"] li,
:root[style*="--USER__letterSpacing"] div,
:root[style*="--USER__letterSpacing"] dt,
:root[style*="--USER__letterSpacing"] dd{
  letter-spacing:var(--USER__letterSpacing) !important;
  font-variant:none !important;
}

:root[style*="readium-noRuby-on"] body rt,
:root[style*="readium-noRuby-on"] body rp{
  display:none;
}

:root[style*="readium-blend-on"] svg,
:root[style*="readium-blend-on"] img{
  background-color:transparent !important;
  mix-blend-mode:multiply !important;
}

:root[style*="--USER__darkenImages"] img{
  -webkit-filter:brightness(var(--USER__darkenImages)) !important;
  filter:brightness(var(--USER__darkenImages)) !important;
}

:root[style*="readium-darken-on"] img{
  -webkit-filter:brightness(80%) !important;
  filter:brightness(80%) !important;
}

:root[style*="--USER__invertImages"] img{
  -webkit-filter:invert(var(--USER__invertImages)) !important;
  filter:invert(var(--USER__invertImages)) !important;
}

:root[style*="readium-invert-on"] img{
  -webkit-filter:invert(100%) !important;
  filter:invert(100%) !important;
}

:root[style*="--USER__darkenImages"][style*="--USER__invertImages"] img{
  -webkit-filter:brightness(var(--USER__darkenImages)) invert(var(--USER__invertImages)) !important;
  filter:brightness(var(--USER__darkenImages)) invert(var(--USER__invertImages)) !important;
}

:root[style*="readium-darken-on"][style*="--USER__invertImages"] img{
  -webkit-filter:brightness(80%) invert(var(--USER__invertImages)) !important;
  filter:brightness(80%) invert(var(--USER__invertImages)) !important;
}

:root[style*="--USER__darkenImages"][style*="readium-invert-on"] img{
  -webkit-filter:brightness(var(--USER__darkenImages)) invert(100%) !important;
  filter:brightness(var(--USER__darkenImages)) invert(100%) !important;
}

:root[style*="readium-darken-on"][style*="readium-invert-on"] img{
  -webkit-filter:brightness(80%) invert(100%) !important;
  filter:brightness(80%) invert(100%) !important;
}

:root[style*="--USER__invertGaiji"] img[class*="gaiji"]{
  -webkit-filter:invert(var(--USER__invertGaiji)) !important;
  filter:invert(var(--USER__invertGaiji)) !important;
}

:root[style*="readium-invertGaiji-on"] img[class*="gaiji"]{
  -webkit-filter:invert(100%) !important;
  filter:invert(100%) !important;
}

:root[style*="readium-normalize-on"]{
  --USER__typeScale:1.2;
}

:root[style*="readium-normalize-on"] p,
:root[style*="readium-normalize-on"] li,
:root[style*="readium-normalize-on"] div,
:root[style*="readium-normalize-on"] pre,
:root[style*="readium-normalize-on"] dd{
  font-size:1rem !important;
}

:root[style*="readium-normalize-on"] h1{
  font-size:1.75rem !important;
  font-size:calc(((1rem * var(--USER__typeScale)) * var(--USER__typeScale)) * var(--USER__typeScale)) !important;
}

:root[style*="readium-normalize-on"] h2{
  font-size:1.5rem !important;
  font-size:calc((1rem * var(--USER__typeScale)) * var(--USER__typeScale)) !important;
}

:root[style*="readium-normalize-on"] h3{
  font-size:1.25rem !important;
  font-size:calc(1rem * var(--USER__typeScale)) !important;
}

:root[style*="readium-normalize-on"] h4,
:root[style*="readium-normalize-on"] h5,
:root[style*="readium-normalize-on"] h6{
  font-size:1rem !important;
}

:root[style*="readium-normalize-on"] small{
  font-size:smaller !important;
}

:root[style*="readium-normalize-on"] sub,
:root[style*="readium-normalize-on"] sup{
  font-size:67.5% !important;
}

:root[style*="readium-normalize-on"][style*="--USER__typeScale"] h1{
  font-size:calc(((1rem * var(--USER__typeScale)) * var(--USER__typeScale)) * var(--USER__typeScale)) !important;
}

:root[style*="readium-normalize-on"][style*="--USER__typeScale"] h2{
  font-size:calc((1rem * var(--USER__typeScale)) * var(--USER__typeScale)) !important;
}

:root[style*="readium-normalize-on"][style*="--USER__typeScale"] h3{
  font-size:calc(1rem * var(--USER__typeScale)) !important;
}

:root[style*="readium-iPadOSPatch-on"] body{
  -webkit-text-size-adjust:none;
}

:root[style*="readium-iPadOSPatch-on"] p, 
:root[style*="readium-iPadOSPatch-on"] h1, 
:root[style*="readium-iPadOSPatch-on"] h2, 
:root[style*="readium-iPadOSPatch-on"] h3, 
:root[style*="readium-iPadOSPatch-on"] h4, 
:root[style*="readium-iPadOSPatch-on"] h5, 
:root[style*="readium-iPadOSPatch-on"] h6, 
:root[style*="readium-iPadOSPatch-on"] li, 
:root[style*="readium-iPadOSPatch-on"] th, 
:root[style*="readium-iPadOSPatch-on"] td, 
:root[style*="readium-iPadOSPatch-on"] dt, 
:root[style*="readium-iPadOSPatch-on"] dd, 
:root[style*="readium-iPadOSPatch-on"] pre, 
:root[style*="readium-iPadOSPatch-on"] address, 
:root[style*="readium-iPadOSPatch-on"] details, 
:root[style*="readium-iPadOSPatch-on"] summary,
:root[style*="readium-iPadOSPatch-on"] figcaption,
:root[style*="readium-iPadOSPatch-on"] div:not(:has(p, h1, h2, h3, h4, h5, h6, li, th, td, dt, dd, pre, address, aside, details, figcaption, summary)),
:root[style*="readium-iPadOSPatch-on"] aside:not(:has(p, h1, h2, h3, h4, h5, h6, li, th, td, dt, dd, pre, address, aside, details, figcaption, summary)){
  -webkit-text-zoom:reset;
}

:root[style*="readium-iPadOSPatch-on"] abbr, 
:root[style*="readium-iPadOSPatch-on"] b, 
:root[style*="readium-iPadOSPatch-on"] bdi, 
:root[style*="readium-iPadOSPatch-on"] bdo, 
:root[style*="readium-iPadOSPatch-on"] cite, 
:root[style*="readium-iPadOSPatch-on"] code, 
:root[style*="readium-iPadOSPatch-on"] dfn, 
:root[style*="readium-iPadOSPatch-on"] em, 
:root[style*="readium-iPadOSPatch-on"] i, 
:root[style*="readium-iPadOSPatch-on"] kbd, 
:root[style*="readium-iPadOSPatch-on"] mark, 
:root[style*="readium-iPadOSPatch-on"] q, 
:root[style*="readium-iPadOSPatch-on"] rp, 
:root[style*="readium-iPadOSPatch-on"] rt, 
:root[style*="readium-iPadOSPatch-on"] ruby, 
:root[style*="readium-iPadOSPatch-on"] s, 
:root[style*="readium-iPadOSPatch-on"] samp, 
:root[style*="readium-iPadOSPatch-on"] small, 
:root[style*="readium-iPadOSPatch-on"] span, 
:root[style*="readium-iPadOSPatch-on"] strong, 
:root[style*="readium-iPadOSPatch-on"] sub, 
:root[style*="readium-iPadOSPatch-on"] sup, 
:root[style*="readium-iPadOSPatch-on"] time, 
:root[style*="readium-iPadOSPatch-on"] u, 
:root[style*="readium-iPadOSPatch-on"] var{
  -webkit-text-zoom:normal;
}

:root[style*="readium-iPadOSPatch-on"] p:not(:has(b, cite, em, i, q, s, small, span, strong)):first-line{
  -webkit-text-zoom:normal;
}`})),Sd=r({default:()=>Cd}),Cd,wd=n((()=>{Cd=`/*!
 * Readium CSS v.2.0.5
 * Copyright (c) 2017–2026. Readium Foundation. All rights reserved.
 * Use of this source code is governed by a BSD-style license which is detailed in the
 * LICENSE file present in the project repository where this source code is maintained.
 * Core maintainer: Jiminy Panoz <jiminy.panoz@edrlab.org> 
 * Contributors: 
 * Daniel Weck
 * Hadrien Gardeur
 * Innovimax
 * L. Le Meur
 * Mickaël Menu
 * k_taka
 */

@namespace url("http://www.w3.org/1999/xhtml");

@namespace epub url("http://www.idpf.org/2007/ops");

@namespace m url("http://www.w3.org/1998/Math/MathML");

@namespace svg url("http://www.w3.org/2000/svg");

@-ms-viewport{
  width:device-width;
}

@viewport{
  width:device-width;
  zoom:1;
}

:root{

  --RS__sans-serif-ja-v:'Hiragino Sans', 'Hiragino Kaku Gothic ProN', 'Hiragino Kaku Gothic Pro', 'ヒラギノ角ゴ W3', 'YuGothic', 'Yu Gothic Medium', 'BIZ UDGothic', 'Yu Gothic', 'ＭＳゴシック', 'MS Gothic', sans-serif;

  --RS__serif-ja-v:'Hiragino Mincho ProN', 'Hiragino Mincho Pro', 'YuMincho', 'BIZ UDMincho', 'Yu Mincho', 'ＭＳ明朝', 'MS Mincho', serif;

  --RS__sans-serif-ja:'Hiragino Sans', 'Hiragino Kaku Gothic ProN', 'Hiragino Kaku Gothic Pro', 'ヒラギノ角ゴ W3', 'YuGothic', 'Yu Gothic Medium', 'BIZ UDPGothic', 'Yu Gothic', 'ＭＳ Ｐゴシック', 'MS PGothic', sans-serif;

  --RS__serif-ja:'Hiragino Mincho ProN', 'Hiragino Mincho Pro', 'YuMincho', 'BIZ UDPMincho', 'Yu Mincho', 'ＭＳ Ｐ明朝', 'MS PMincho', serif;

  --RS__monospaceTf:ui-monospace, 'Andale Mono', 'Cascadia Code', 'Source Code Pro', Menlo, Consolas, 'DejaVu Sans Mono', monospace;

  --RS__humanistTf:Seravek, Calibri, 'Gill Sans Nova', Roboto, Ubuntu, 'DejaVu Sans', source-sans-pro, sans-serif;

  --RS__sansTf:-ui-sans-serif, -apple-system, system-ui, BlinkMacSystemFont, 'Segoe UI Variable', 'Segoe UI', Inter, Roboto, 'Helvetica Neue', 'Arial Nova', 'Liberation Sans', Arial, sans-serif;

  --RS__modernTf:Athelas, Constantia, Charter, 'Bitstream Charter', Cambria, 'Georgia Pro', Georgia, serif;

  --RS__oldStyleTf:'Iowan Old Style', Sitka, 'Sitka Text', Palatino, 'Book Antiqua', 'URW Palladio L', P052, serif;

  --RS__zh-HK-lineHeightCompensation:1.167;

  --RS__zh-HK-baseFontFamily:'方體', 'PingFang HK', '方體', 'PingFang TC', '黑體', 'Heiti TC', 'Microsoft JhengHei UI', 'Microsoft JhengHei', Roboto, Noto, 'Noto Sans CJK TC', sans-serif;

  --RS__zh-TW-lineHeightCompensation:1.167;

  --RS__zh-TW-baseFontFamily:'方體', 'PingFang TC', '黑體', 'Heiti TC', 'Microsoft JhengHei UI', 'Microsoft JhengHei', Roboto, Noto, 'Noto Sans CJK TC', sans-serif;

  --RS__zh-Hant-lineHeightCompensation:1.167;

  --RS__zh-Hant-baseFontFamily:'方體', 'PingFang TC', '黑體', 'Heiti TC', 'Microsoft JhengHei UI', 'Microsoft JhengHei', Roboto, Noto, 'Noto Sans CJK TC', sans-serif;

  --RS__zh-lineHeightCompensation:1.167;

  --RS__zh-baseFontFamily:'方体', 'PingFang SC', '黑体', 'Heiti SC', 'Microsoft JhengHei UI', 'Microsoft JhengHei', Roboto, Noto, 'Noto Sans CJK SC', sans-serif;

  --RS__th-lineHeightCompensation:1.067;

  --RS__th-baseFontFamily:Thonburi, 'Leelawadee UI', 'Cordia New', Roboto, Noto, 'Noto Sans Thai', sans-serif;

  --RS__te-baseFontFamily:'Kohinoor Telugu', 'Telugu Sangam MN', 'Nirmala UI', Gautami, Roboto, Noto, 'Noto Sans Telugu', sans-serif;

  --RS__ta-lineHeightCompensation:1.067;

  --RS__ta-baseFontFamily:'Tamil Sangam MN', 'Nirmala UI', Latha, Roboto, Noto, 'Noto Sans Tamil', sans-serif;

  --RS__si-lineHeightCompensation:1.167;

  --RS__si-baseFontFamily:'Sinhala Sangam MN', 'Nirmala UI', 'Iskoola Pota', Roboto, Noto, 'Noto Sans Sinhala', sans-serif;

  --RS__pa-lineHeightCompensation:1.1;

  --RS__pa-baseFontFamily:'Gurmukhi MN', 'Nirmala UI', Kartika, Roboto, Noto, 'Noto Sans Gurmukhi', sans-serif;

  --RS__or-lineHeightCompensation:1.167;

  --RS__or-baseFontFamily:'Oriya Sangam MN', 'Nirmala UI', Kalinga, Roboto, Noto, 'Noto Sans Oriya', sans-serif;

  --RS__ml-lineHeightCompensation:1.067;

  --RS__ml-baseFontFamily:'Malayalam Sangam MN', 'Nirmala UI', Kartika, Roboto, Noto, 'Noto Sans Malayalam', sans-serif;

  --RS__lo-baseFontFamily:'Lao Sangam MN', 'Leelawadee UI', 'Lao UI', Roboto, Noto, 'Noto Sans Lao', sans-serif;

  --RS__ko-lineHeightCompensation:1.167;

  --RS__ko-baseFontFamily:'Nanum Gothic', 'Apple SD Gothic Neo', 'Malgun Gothic', Roboto, Noto, 'Noto Sans CJK KR', sans-serif;

  --RS__kn-lineHeightCompensation:1.1;

  --RS__kn-baseFontFamily:'Kannada Sangam MN', 'Nirmala UI', Tunga, Roboto, Noto, 'Noto Sans Kannada', sans-serif;

  --RS__km-lineHeightCompensation:1.067;

  --RS__km-baseFontFamily:'Khmer Sangam MN', 'Leelawadee UI', 'Khmer UI', Roboto, Noto, 'Noto Sans Khmer', sans-serif;

  --RS__ja-lineHeightCompensation:1.167;

  --RS__ja-baseFontFamily:YuGothic, 'Hiragino Maru Gothic ProN', 'Hiragino Sans', 'Yu Gothic UI', 'Meiryo UI', 'MS Gothic', Roboto, Noto, 'Noto Sans CJK JP', sans-serif;

  --RS__iu-baseFontFamily:'Euphemia UCAS', Euphemia, Roboto, Noto, 'Noto Sans Canadian Aboriginal', sans-serif;

  --RS__hy-baseFontFamily:Mshtakan, Sylfaen, Roboto, Noto, 'Noto Serif Armenian', serif;

  --RS__hi-lineHeightCompensation:1.1;

  --RS__hi-baseFontFamily:'Kohinoor Devanagari', 'Devanagari Sangam MN', Kokila, 'Nirmala UI', Roboto, Noto, 'Noto Sans Devanagari', sans-serif;

  --RS__he-lineHeightCompensation:1.1;

  --RS__he-baseFontFamily:'New Peninim MT', 'Arial Hebrew', Gisha, 'Times New Roman', Roboto, Noto, 'Noto Sans Hebrew', sans-serif;

  --RS__gu-lineHeightCompensation:1.167;

  --RS__gu-baseFontFamily:'Gujarati Sangam MN', 'Nirmala UI', Shruti, Roboto, Noto, 'Noto Sans Gujarati', sans-serif;

  --RS__fa-baseFontFamily:'Geeza Pro', 'Arabic Typesetting', Roboto, Noto, 'Noto Naskh Arabic', 'Times New Roman', serif;

  --RS__chr-lineHeightCompensation:1.167;

  --RS__chr-baseFontFamily:'Plantagenet Cherokee', Roboto, Noto, 'Noto Sans Cherokee';

  --RS__bo-baseFontFamily:Kailasa, 'Microsoft Himalaya', Roboto, Noto, 'Noto Sans Tibetan', sans-serif;

  --RS__bn-lineHeightCompensation:1.067;

  --RS__bn-baseFontFamily:'Kohinoor Bangla', 'Bangla Sangam MN', Vrinda, Roboto, Noto, 'Noto Sans Bengali', sans-serif;

  --RS__ar-baseFontFamily:'Geeza Pro', 'Arabic Typesetting', Roboto, Noto, 'Noto Naskh Arabic', 'Times New Roman', serif;

  --RS__am-lineHeightCompensation:1.167;

  --RS__am-baseFontFamily:Kefa, Nyala, Roboto, Noto, 'Noto Sans Ethiopic', serif;

  --RS__latin-lineHeightCompensation:1;

  --RS__latin-baseFontFamily:var(--RS__oldStyleTf);
  --RS__baseFontFamily:var(--RS__latin-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__latin-lineHeightCompensation);
  --RS__baseLineHeight:calc(1.5 * var(--RS__lineHeightCompensation));

  --RS__selectionTextColor:inherit;

  --RS__selectionBackgroundColor:#b4d8fe;

  --RS__visitedColor:#551A8B;

  --RS__linkColor:#0000EE;

  --RS__textColor:#121212;

  --RS__backgroundColor:#FFFFFF;
  color:var(--RS__textColor) !important;

  background-color:var(--RS__backgroundColor) !important;
}

::-moz-selection{
  color:var(--RS__selectionTextColor);
  background-color:var(--RS__selectionBackgroundColor);
}

::selection{
  color:var(--RS__selectionTextColor);
  background-color:var(--RS__selectionBackgroundColor);
}

html{
  font-family:var(--RS__baseFontFamily);
  line-height:1.6;
  line-height:var(--RS__baseLineHeight);
  text-rendering:optimizelegibility;
}

h1, h2, h3{
  line-height:normal;
}

:lang(ja),
:lang(zh),
:lang(ko){
  word-wrap:break-word;
  -webkit-line-break:strict;
  -epub-line-break:strict;
  line-break:strict;
}

math{
  font-family:"Latin Modern Math", "STIX Two Math", "XITS Math", "STIX Math", "Libertinus Math", "TeX Gyre Termes Math", "TeX Gyre Bonum Math", "TeX Gyre Schola", "DejaVu Math TeX Gyre", "TeX Gyre Pagella Math", "Asana Math", "Cambria Math", "Lucida Bright Math", "Minion Math", STIXGeneral, STIXSizeOneSym, Symbol, "Times New Roman", serif;
}

:lang(am){
  --RS__baseFontFamily:var(--RS__am-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__am-lineHeightCompensation);
}

:lang(ar){
  --RS__baseFontFamily:var(--RS__ar-baseFontFamily);
}

:lang(bn){
  --RS__baseFontFamily:var(--RS__bn-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__bn-lineHeightCompensation);
}

:lang(bo){
  --RS__baseFontFamily:var(--RS__bo-baseFontFamily);
}

:lang(chr){
  --RS__baseFontFamily:var(--RS__chr-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__chr-lineHeightCompensation);
}

:lang(fa){
  --RS__baseFontFamily:var(--RS__fa-baseFontFamily);
}

:lang(gu){
  --RS__baseFontFamily:var(--RS__gu-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__gu-lineHeightCompensation);
}

:lang(he){
  --RS__baseFontFamily:var(--RS__he-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__he-lineHeightCompensation);
}

:lang(hi){
  --RS__baseFontFamily:var(--RS__hi-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__hi-lineHeightCompensation);
}

:lang(hy){
  --RS__baseFontFamily:var(--RS__hy-baseFontFamily);
}

:lang(iu){
  --RS__baseFontFamily:var(--RS__iu-baseFontFamily);
}

:lang(ja){
  --RS__baseFontFamily:var(--RS__ja-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__ja-lineHeightCompensation);
}

:lang(km){
  --RS__baseFontFamily:var(--RS__km-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__km-lineHeightCompensation);
}

:lang(kn){
  --RS__baseFontFamily:var(--RS__kn-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__kn-lineHeightCompensation);
}

:lang(ko){
  --RS__baseFontFamily:var(--RS__ko-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__ko-lineHeightCompensation);
}

:lang(lo){
  --RS__baseFontFamily:var(--RS__lo-baseFontFamily);
}

:lang(ml){
  --RS__baseFontFamily:var(--RS__ml-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__ml-lineHeightCompensation);
}

:lang(or){
  --RS__baseFontFamily:var(--RS__or-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__or-lineHeightCompensation);
}

:lang(pa){
  --RS__baseFontFamily:var(--RS__pa-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__pa-lineHeightCompensation);
}

:lang(si){
  --RS__baseFontFamily:var(--RS__si-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__si-lineHeightCompensation);
}

:lang(ta){
  --RS__baseFontFamily:var(--RS__ta-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__ta-lineHeightCompensation);
}

:lang(te){
  --RS__baseFontFamily:var(--RS__te-baseFontFamily);
}

:lang(th){
  --RS__baseFontFamily:var(--RS__th-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__th-lineHeightCompensation);
}

:lang(zh){
  --RS__baseFontFamily:var(--RS__zh-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__zh-lineHeightCompensation);
}

:lang(zh-Hant){
  --RS__baseFontFamily:var(--RS__zh-Hant-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__zh-Hant-lineHeightCompensation);
}

:lang(zh-TW){
  --RS__baseFontFamily:var(--RS__zh-TW-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__zh-TW-lineHeightCompensation);
}

:lang(zh-HK){
  --RS__baseFontFamily:var(--RS__zh-HK-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__zh-HK-lineHeightCompensation);
}

body{
  widows:2;
  orphans:2;
}

figcaption, th, td{
  widows:1;
  orphans:1;
}

h2, h3, h4, h5, h6, dt,
hr, caption{
  -webkit-column-break-after:avoid;
  page-break-after:avoid;
  break-after:avoid;
}

h1, h2, h3, h4, h5, h6, dt,
figure, tr{
  -webkit-column-break-inside:avoid;
  page-break-inside:avoid;
  break-inside:avoid;
}

body{
  -webkit-hyphenate-character:"\\002D";
  -moz-hyphenate-character:"\\002D";
  -ms-hyphenate-character:"\\002D";
  hyphenate-character:"\\002D";
  -webkit-hyphenate-limit-lines:3;
  -ms-hyphenate-limit-lines:3;
  hyphenate-limit-lines:3;
}

h1, h2, h3, h4, h5, h6, dt,
figcaption, pre, caption, address,
center, code, var{
  -ms-hyphens:none;
  -moz-hyphens:none;
  -webkit-hyphens:none;
  -epub-hyphens:none;
  hyphens:none;
}

body{
  font-variant-numeric:oldstyle-nums proportional-nums;
}

:lang(ja) body,
:lang(zh) body,
:lang(ko) body{
  font-variant-numeric:lining-nums proportional-nums;
}

h1, h2, h3, h4, h5, h6, dt{
  font-variant-numeric:lining-nums proportional-nums;
}

table{
  font-variant-numeric:lining-nums tabular-nums;
}

code, var{
  font-variant-ligatures:none;
  font-variant-numeric:lining-nums tabular-nums slashed-zero;
}

rt{
  font-variant-east-asian:ruby;
}

:lang(ar){
  font-variant-ligatures:common-ligatures;
}

:lang(ko){
  font-kerning:normal;
}

hr{
  color:inherit;
  border-color:currentcolor;
}

table, th, td{
  border-color:currentcolor;
}

figure, blockquote{
  margin:1em 5%;
}

ul, ol{
  padding-left:5%;
}

dd{
  margin-left:5%;
}

pre{
  white-space:pre-wrap;
  -ms-tab-size:2;
  -moz-tab-size:2;
  -webkit-tab-size:2;
  tab-size:2;
}

abbr[title], acronym[title]{
  text-decoration:dotted underline;
}

nobr wbr{
  white-space:normal;
}

ruby > rt, ruby > rp{
  -webkit-user-select:none;
  -moz-user-select:none;
  -ms-user-select:none;
  user-select:none;
}

*:lang(ja):not(:lang(ja-Latn)):not(:lang(ja-Cyrl)),
*:lang(zh):not(:lang(zh-Latn)):not(:lang(zh-Cyrl)),
*:lang(ko):not(:lang(ko-Latn)):not(:lang(ko-Cyrl)),
:lang(ja):not(:lang(ja-Latn)):not(:lang(ja-Cyrl)) cite, 
:lang(ja):not(:lang(ja-Latn)):not(:lang(ja-Cyrl)) dfn, 
:lang(ja):not(:lang(ja-Latn)):not(:lang(ja-Cyrl)) em, 
:lang(ja):not(:lang(ja-Latn)):not(:lang(ja-Cyrl)) i,
:lang(zh):not(:lang(zh-Latn)):not(:lang(zh-Cyrl)) cite, 
:lang(zh):not(:lang(zh-Latn)):not(:lang(zh-Cyrl)) dfn, 
:lang(zh):not(:lang(zh-Latn)):not(:lang(zh-Cyrl)) em, 
:lang(zh):not(:lang(zh-Latn)):not(:lang(zh-Cyrl)) i,
:lang(ko):not(:lang(ko-Latn)):not(:lang(ko-Cyrl)) cite, 
:lang(ko):not(:lang(ko-Latn)):not(:lang(ko-Cyrl)) dfn, 
:lang(ko):not(:lang(ko-Latn)):not(:lang(ko-Cyrl)) em, 
:lang(ko):not(:lang(ko-Latn)):not(:lang(ko-Cyrl)) i{
  font-style:normal;
}

:lang(ja) a,
:lang(zh) a,
:lang(ko) a{
  text-decoration:none;
}

:root{
  --RS__maxMediaWidth:100%;
  --RS__maxMediaHeight:100vw;
  --RS__boxSizingMedia:border-box;
  --RS__boxSizingTable:border-box;
}

a, a span, span a, h1, h2, h3, h4, h5, h6{
  word-wrap:break-word;
}

div{
  max-width:var(--RS__maxMediaHeight);
}

img, svg|svg, video{
  object-fit:contain;

  width:auto;
  height:auto;
  max-width:var(--RS__maxMediaHeight);
  max-height:var(--RS__maxMediaWidth) !important;
  box-sizing:var(--RS__boxSizingMedia);
  -webkit-column-break-inside:avoid;
  page-break-inside:avoid;
  break-inside:avoid;
}

@supports (zoom: 1) and (not ((-webkit-column-axis: horizontal) and (-webkit-column-progression: normal))){

  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] img,
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] svg|svg,
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] video,
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] div{
    zoom:calc(100% / var(--USER__fontSize));
  }
}

audio{
  max-width:100%;
  -webkit-column-break-inside:avoid;
  page-break-inside:avoid;
  break-inside:avoid;
}

table{
  max-height:var(--RS__maxMediaWidth);
  box-sizing:var(--RS__boxSizingTable);
}`})),Td=r({default:()=>Ed}),Ed,Dd=n((()=>{Ed=`/*!
 * Readium CSS v.2.0.5
 * Copyright (c) 2017–2026. Readium Foundation. All rights reserved.
 * Use of this source code is governed by a BSD-style license which is detailed in the
 * LICENSE file present in the project repository where this source code is maintained.
 * Core maintainer: Jiminy Panoz <jiminy.panoz@edrlab.org> 
 * Contributors: 
 * Daniel Weck
 * Hadrien Gardeur
 * Innovimax
 * L. Le Meur
 * Mickaël Menu
 * k_taka
 */

@namespace url("http://www.w3.org/1999/xhtml");

@namespace epub url("http://www.idpf.org/2007/ops");

@namespace m url("http://www.w3.org/1998/Math/MathML");

@namespace svg url("http://www.w3.org/2000/svg");

:root{

  --RS__compFontFamily:var(--RS__baseFontFamily);
  --RS__codeFontFamily:var(--RS__monospaceTf);

  --RS__typeScale:1.125;
  --RS__baseFontSize:87.5%;

  --RS__flowSpacing:1.5rem;
  --RS__paraSpacing:0;
  --RS__paraIndent:1em;

  --RS__linkColor:#0000EE;
  --RS__visitedColor:#551A8B;

  --RS__primaryColor:;
  --RS__secondaryColor:;
}

:root:lang(zh){
  --RS__paraIndent:2em;
}

:lang("mn-Mong"){
  --RS__baseFontSize:100%;
}

body{
  font-size:var(--RS__baseFontSize);
  text-align:justify;
  text-justify:inter-character;
}

h1, h2, h3, h4, h5, h6{
  font-family:var(--RS__baseFontFamily);
  text-align:left;
  text-align:start;
}

blockquote, figure, p, pre,
aside, footer, form, hr{
  margin-right:var(--RS__flowSpacing);
  margin-left:var(--RS__flowSpacing);
}

p{
  margin-right:var(--RS__paraSpacing);
  margin-left:var(--RS__paraSpacing);
  text-indent:var(--RS__paraIndent);
}

pre{
  font-family:var(--RS__codeFontFamily);
}

code, kbd, samp, tt{
  font-family:var(--RS__codeFontFamily);
}

sub, sup{
  position:relative;
  font-size:67.5%;
  line-height:1;
}

sub{
  left:-0.2ex;
}

sup{
  right:0;
}

em{
  -webkit-text-emphasis:sesame;
  -epub-text-emphasis:sesame;
  text-emphasis:sesame;
}

:link{
  color:var(--RS__linkColor);
}

:visited{
  color:var(--RS__visitedColor);
}

h1{
  margin-right:calc(var(--RS__flowSpacing) * 2);
  margin-left:calc(var(--RS__flowSpacing) * 2);
  font-size:calc(((1em * var(--RS__typeScale)) * var(--RS__typeScale)) * var(--RS__typeScale));
  text-indent:2rem;
}

h2{
  margin-right:calc(var(--RS__flowSpacing) * 2);
  margin-left:var(--RS__flowSpacing);
  font-size:calc((1em * var(--RS__typeScale)) * var(--RS__typeScale));
  text-indent:3rem;
}

h3{
  margin-right:var(--RS__flowSpacing);
  margin-left:var(--RS__flowSpacing);
  font-size:calc(1em * var(--RS__typeScale));
  text-indent:4rem;
}

h4{
  margin-right:var(--RS__flowSpacing);
  margin-left:var(--RS__flowSpacing);
  font-family:var(--RS__compFontFamily);
  font-size:1em;
  text-indent:4rem;
}

h5{
  margin-right:var(--RS__flowSpacing);
  margin-left:var(--RS__flowSpacing);
  font-family:var(--RS__compFontFamily);
  font-size:smaller;
  text-indent:4rem;
}

h6{
  margin-right:var(--RS__flowSpacing);
  margin-left:0;
  font-family:var(--RS__compFontFamily);
  font-size:smaller;
  font-weight:normal;
  text-indent:4rem;
}

dl, ol, ul{
  margin-right:var(--RS__flowSpacing);
  margin-left:var(--RS__flowSpacing);
}

table{
  margin:0 var(--RS__flowSpacing);
  border:1px solid currentcolor;
  border-collapse:collapse;
  empty-cells:show;
}

thead, tbody, tfoot, table > tr{
  vertical-align:top;
}

th{
  text-align:left;
}

th, td{
  padding:4px;
  border:1px solid currentcolor;
}`})),Od=r({default:()=>kd}),kd,Ad=n((()=>{kd=`/*!
 * Readium CSS v.2.0.5
 * Copyright (c) 2017–2026. Readium Foundation. All rights reserved.
 * Use of this source code is governed by a BSD-style license which is detailed in the
 * LICENSE file present in the project repository where this source code is maintained.
 * Core maintainer: Jiminy Panoz <jiminy.panoz@edrlab.org> 
 * Contributors: 
 * Daniel Weck
 * Hadrien Gardeur
 * Innovimax
 * L. Le Meur
 * Mickaël Menu
 * k_taka
 */

@namespace url("http://www.w3.org/1999/xhtml");

@namespace epub url("http://www.idpf.org/2007/ops");

@namespace m url("http://www.w3.org/1998/Math/MathML");

@namespace svg url("http://www.w3.org/2000/svg");

:root{

   --RS__viewportWidth:100%;

   --RS__pageGutter:0;

   --RS__defaultLineLength:100%;

   --RS__colGap:0;

   --RS__colCount:1;

   --RS__colWidth:100vw;
}

@page{
  margin:0 !important;
}

:root{
  position:relative;

  -webkit-column-width:var(--RS__colWidth);
  -moz-column-width:var(--RS__colWidth);
  column-width:var(--RS__colWidth);
  -webkit-column-count:var(--RS__colCount);
  -moz-column-count:var(--RS__colCount);
  column-count:var(--RS__colCount);

  -webkit-column-gap:var(--RS__colGap);
  -moz-column-gap:var(--RS__colGap);
  column-gap:var(--RS__colGap);
  -moz-column-fill:auto;
  column-fill:auto;
  width:100%;
  height:100vh;
  max-width:100%;
  max-height:100vh;
  min-width:100%;
  min-height:100vh;
  padding:0 !important;
  margin:0 !important;
  font-size:1rem !important;
  box-sizing:border-box;

  hanging-punctuation:last allow-end;
  -webkit-touch-callout:none;
  -ms-writing-mode:tb-rl;
  -webkit-writing-mode:vertical-rl;
  writing-mode:vertical-rl;
}

:root:lang(mn-Mong){
  -ms-writing-mode:tb;
  -webkit-writing-mode:vertical-lr;
  writing-mode:vertical-lr;
}

body{
  width:100%;
  max-height:var(--RS__defaultLineLength) !important;
  margin:auto 0 !important;
  box-sizing:border-box;
}

:root:not([style*="readium-scroll-on"]) body{
  padding:var(--RS__pageGutter) 0 !important;
}

:root:not([style*="readium-noOverflow-on"]) body{
  overflow:hidden;
}

@supports (overflow: clip){

  :root:not([style*="readium-noOverflow-on"]){
     overflow:clip;
  }

  :root:not([style*="readium-noOverflow-on"]) body{
     overflow:clip;
     overflow-clip-margin:content-box;
  }
}

:root[style*="readium-scroll-on"],
:root[style*="readium-noVerticalPagination-on"]{
  -webkit-columns:auto auto !important;
  -moz-columns:auto auto !important;
  columns:auto auto !important;
  width:auto !important;
  max-width:none !important;
  max-height:100vh !important;
  min-width:0 !important;
}

:root[style*="readium-scroll-on"] body,
:root[style*="readium-noVerticalPagination-on"] body{
  max-width:var(--RS__defaultLineLength) !important;
  box-sizing:border-box !important;
}

@supports (overflow: clip){

  :root[style*="readium-scroll-on"]:not([style*="readium-noOverflow-on"]){
     overflow:auto;
  }

  :root[style*="readium-scroll-on"]:not([style*="readium-noOverflow-on"]) body{
     overflow:clip;
  }
}

:root[style*="readium-scroll-on"][style*="--RS__scrollPaddingTop"] body{
  padding-top:var(--RS__scrollPaddingTop) !important;
}

:root[style*="readium-scroll-on"][style*="--RS__scrollPaddingBottom"] body{
  padding-bottom:var(--RS__scrollPaddingBottom) !important;
}

:root[style*="readium-scroll-on"][style*="--RS__scrollPaddingLeft"] body{
  padding-left:var(--RS__scrollPaddingLeft) !important;
}

:root[style*="readium-scroll-on"][style*="--RS__scrollPaddingRight"] body{
  padding-right:var(--RS__scrollPaddingRight) !important;
}

:root[style*="--USER__backgroundColor"]{
  background-color:var(--USER__backgroundColor) !important;
}

:root[style*="--USER__backgroundColor"] *{
  background-color:transparent !important;
}

:root[style*="--USER__textColor"]{
  color:var(--USER__textColor) !important;
}

:root[style*="--USER__textColor"] *:not(a){
  color:inherit !important;
  background-color:transparent !important;
  border-color:currentcolor !important;
}

:root[style*="--USER__textColor"] svg text{
  fill:currentcolor !important;
  stroke:none !important;
}

:root[style*="--USER__linkColor"] a:link,
:root[style*="--USER__linkColor"] a:link *{
  color:var(--USER__linkColor) !important;
}

:root[style*="--USER__visitedColor"] a:visited,
:root[style*="--USER__visitedColor"] a:visited *{
  color:var(--USER__visitedColor) !important;
}

:root[style*="--USER__selectionBackgroundColor"][style*="--USER__selectionTextColor"] ::-moz-selection{
  color:var(--USER__selectionTextColor) !important;
  background-color:var(--USER__selectionBackgroundColor) !important;
}

:root[style*="--USER__selectionBackgroundColor"][style*="--USER__selectionTextColor"] ::selection{
  color:var(--USER__selectionTextColor) !important;
  background-color:var(--USER__selectionBackgroundColor) !important;
}

:root[style*="--USER__lineLength"] body{
    max-height:var(--USER__lineLength) !important;
  }

:root[style*="--USER__fontFamily"]{
  font-family:var(--USER__fontFamily) !important;
}

:root[style*="--USER__fontFamily"] *{
  font-family:revert !important;
}

:root:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] body{
  zoom:var(--USER__fontSize) !important;
}

:root:not([style*="readium-deprecatedFontSize-on"])[style*="readium-iOSPatch-on"][style*="--USER__fontSize"] body{
  -webkit-text-size-adjust:var(--USER__fontSize) !important;
}

@supports selector(figure:has(> img)){

  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] figure:has(> img),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] figure:has(> video),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] figure:has(> svg),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] figure:has(> canvas),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] figure:has(> iframe),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] figure:has(> audio),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] div:has(> img:only-child),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] div:has(> video:only-child),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] div:has(> svg:only-child),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] div:has(> canvas:only-child),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] div:has(> iframe:only-child),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] div:has(> audio:only-child),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] table{
    zoom:calc(100% / var(--USER__fontSize)) !important;
  }

  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] figcaption,
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] caption,
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] td,
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] th{
    zoom:var(--USER__fontSize) !important;
  }
}

@supports not (zoom: 1){

  :root[style*="--USER__fontSize"]{
    font-size:var(--USER__fontSize) !important;
  }
}

:root[style*="readium-deprecatedFontSize-on"][style*="--USER__fontSize"]{
  font-size:var(--USER__fontSize) !important;
}

:root[style*="--USER__lineHeight"]{
  line-height:var(--USER__lineHeight) !important;
}

:root[style*="--USER__lineHeight"] body,
:root[style*="--USER__lineHeight"] p,
:root[style*="--USER__lineHeight"] li,
:root[style*="--USER__lineHeight"] div{
  line-height:var(--USER__lineHeight) !important;
}

:root[style*="--USER__paraSpacing"] p{
  margin-right:var(--USER__paraSpacing) !important;
  margin-left:var(--USER__paraSpacing) !important;
}

:root[style*="--USER__fontWeight"] body{
  font-weight:var(--USER__fontWeight) !important;
}

:root[style*="--USER__fontWeight"] b,
:root[style*="--USER__fontWeight"] strong{
  font-weight:bolder;
}

:root[style*="--USER__fontWidth"] body{
  font-stretch:var(--USER__fontWidth) !important;
}

:root[style*="--USER__fontOpticalSizing"] body{
  font-optical-sizing:var(--USER__fontOpticalSizing) !important;
}

:root[style*="--USER__letterSpacing"] h1,
:root[style*="--USER__letterSpacing"] h2,
:root[style*="--USER__letterSpacing"] h3,
:root[style*="--USER__letterSpacing"] h4,
:root[style*="--USER__letterSpacing"] h5,
:root[style*="--USER__letterSpacing"] h6,
:root[style*="--USER__letterSpacing"] p,
:root[style*="--USER__letterSpacing"] li,
:root[style*="--USER__letterSpacing"] div,
:root[style*="--USER__letterSpacing"] dt,
:root[style*="--USER__letterSpacing"] dd{
  letter-spacing:var(--USER__letterSpacing) !important;
  font-variant:none !important;
}

:root[style*="readium-noRuby-on"] body rt,
:root[style*="readium-noRuby-on"] body rp{
  display:none;
}

:root[style*="readium-blend-on"] svg,
:root[style*="readium-blend-on"] img{
  background-color:transparent !important;
  mix-blend-mode:multiply !important;
}

:root[style*="--USER__darkenImages"] img{
  -webkit-filter:brightness(var(--USER__darkenImages)) !important;
  filter:brightness(var(--USER__darkenImages)) !important;
}

:root[style*="readium-darken-on"] img{
  -webkit-filter:brightness(80%) !important;
  filter:brightness(80%) !important;
}

:root[style*="--USER__invertImages"] img{
  -webkit-filter:invert(var(--USER__invertImages)) !important;
  filter:invert(var(--USER__invertImages)) !important;
}

:root[style*="readium-invert-on"] img{
  -webkit-filter:invert(100%) !important;
  filter:invert(100%) !important;
}

:root[style*="--USER__darkenImages"][style*="--USER__invertImages"] img{
  -webkit-filter:brightness(var(--USER__darkenImages)) invert(var(--USER__invertImages)) !important;
  filter:brightness(var(--USER__darkenImages)) invert(var(--USER__invertImages)) !important;
}

:root[style*="readium-darken-on"][style*="--USER__invertImages"] img{
  -webkit-filter:brightness(80%) invert(var(--USER__invertImages)) !important;
  filter:brightness(80%) invert(var(--USER__invertImages)) !important;
}

:root[style*="--USER__darkenImages"][style*="readium-invert-on"] img{
  -webkit-filter:brightness(var(--USER__darkenImages)) invert(100%) !important;
  filter:brightness(var(--USER__darkenImages)) invert(100%) !important;
}

:root[style*="readium-darken-on"][style*="readium-invert-on"] img{
  -webkit-filter:brightness(80%) invert(100%) !important;
  filter:brightness(80%) invert(100%) !important;
}

:root[style*="--USER__invertGaiji"] img[class*="gaiji"]{
  -webkit-filter:invert(var(--USER__invertGaiji)) !important;
  filter:invert(var(--USER__invertGaiji)) !important;
}

:root[style*="readium-invertGaiji-on"] img[class*="gaiji"]{
  -webkit-filter:invert(100%) !important;
  filter:invert(100%) !important;
}

:root[style*="readium-normalize-on"]{
  --USER__typeScale:1.2;
}

:root[style*="readium-normalize-on"] p,
:root[style*="readium-normalize-on"] li,
:root[style*="readium-normalize-on"] div,
:root[style*="readium-normalize-on"] pre,
:root[style*="readium-normalize-on"] dd{
  font-size:1rem !important;
}

:root[style*="readium-normalize-on"] h1{
  font-size:1.75rem !important;
  font-size:calc(((1rem * var(--USER__typeScale)) * var(--USER__typeScale)) * var(--USER__typeScale)) !important;
}

:root[style*="readium-normalize-on"] h2{
  font-size:1.5rem !important;
  font-size:calc((1rem * var(--USER__typeScale)) * var(--USER__typeScale)) !important;
}

:root[style*="readium-normalize-on"] h3{
  font-size:1.25rem !important;
  font-size:calc(1rem * var(--USER__typeScale)) !important;
}

:root[style*="readium-normalize-on"] h4,
:root[style*="readium-normalize-on"] h5,
:root[style*="readium-normalize-on"] h6{
  font-size:1rem !important;
}

:root[style*="readium-normalize-on"] small{
  font-size:smaller !important;
}

:root[style*="readium-normalize-on"] sub,
:root[style*="readium-normalize-on"] sup{
  font-size:67.5% !important;
}

:root[style*="readium-normalize-on"][style*="--USER__typeScale"] h1{
  font-size:calc(((1rem * var(--USER__typeScale)) * var(--USER__typeScale)) * var(--USER__typeScale)) !important;
}

:root[style*="readium-normalize-on"][style*="--USER__typeScale"] h2{
  font-size:calc((1rem * var(--USER__typeScale)) * var(--USER__typeScale)) !important;
}

:root[style*="readium-normalize-on"][style*="--USER__typeScale"] h3{
  font-size:calc(1rem * var(--USER__typeScale)) !important;
}

:root[style*="readium-iPadOSPatch-on"] body{
  -webkit-text-size-adjust:none;
}

:root[style*="readium-iPadOSPatch-on"] p, 
:root[style*="readium-iPadOSPatch-on"] h1, 
:root[style*="readium-iPadOSPatch-on"] h2, 
:root[style*="readium-iPadOSPatch-on"] h3, 
:root[style*="readium-iPadOSPatch-on"] h4, 
:root[style*="readium-iPadOSPatch-on"] h5, 
:root[style*="readium-iPadOSPatch-on"] h6, 
:root[style*="readium-iPadOSPatch-on"] li, 
:root[style*="readium-iPadOSPatch-on"] th, 
:root[style*="readium-iPadOSPatch-on"] td, 
:root[style*="readium-iPadOSPatch-on"] dt, 
:root[style*="readium-iPadOSPatch-on"] dd, 
:root[style*="readium-iPadOSPatch-on"] pre, 
:root[style*="readium-iPadOSPatch-on"] address, 
:root[style*="readium-iPadOSPatch-on"] details, 
:root[style*="readium-iPadOSPatch-on"] summary,
:root[style*="readium-iPadOSPatch-on"] figcaption,
:root[style*="readium-iPadOSPatch-on"] div:not(:has(p, h1, h2, h3, h4, h5, h6, li, th, td, dt, dd, pre, address, aside, details, figcaption, summary)),
:root[style*="readium-iPadOSPatch-on"] aside:not(:has(p, h1, h2, h3, h4, h5, h6, li, th, td, dt, dd, pre, address, aside, details, figcaption, summary)){
  -webkit-text-zoom:reset;
}

:root[style*="readium-iPadOSPatch-on"] abbr, 
:root[style*="readium-iPadOSPatch-on"] b, 
:root[style*="readium-iPadOSPatch-on"] bdi, 
:root[style*="readium-iPadOSPatch-on"] bdo, 
:root[style*="readium-iPadOSPatch-on"] cite, 
:root[style*="readium-iPadOSPatch-on"] code, 
:root[style*="readium-iPadOSPatch-on"] dfn, 
:root[style*="readium-iPadOSPatch-on"] em, 
:root[style*="readium-iPadOSPatch-on"] i, 
:root[style*="readium-iPadOSPatch-on"] kbd, 
:root[style*="readium-iPadOSPatch-on"] mark, 
:root[style*="readium-iPadOSPatch-on"] q, 
:root[style*="readium-iPadOSPatch-on"] rp, 
:root[style*="readium-iPadOSPatch-on"] rt, 
:root[style*="readium-iPadOSPatch-on"] ruby, 
:root[style*="readium-iPadOSPatch-on"] s, 
:root[style*="readium-iPadOSPatch-on"] samp, 
:root[style*="readium-iPadOSPatch-on"] small, 
:root[style*="readium-iPadOSPatch-on"] span, 
:root[style*="readium-iPadOSPatch-on"] strong, 
:root[style*="readium-iPadOSPatch-on"] sub, 
:root[style*="readium-iPadOSPatch-on"] sup, 
:root[style*="readium-iPadOSPatch-on"] time, 
:root[style*="readium-iPadOSPatch-on"] u, 
:root[style*="readium-iPadOSPatch-on"] var{
  -webkit-text-zoom:normal;
}

:root[style*="readium-iPadOSPatch-on"] p:not(:has(b, cite, em, i, q, s, small, span, strong)):first-line{
  -webkit-text-zoom:normal;
}`})),jd=r({default:()=>Md}),Md,Nd=n((()=>{Md=`/*!
 * Readium CSS v.2.0.5
 * Copyright (c) 2017–2026. Readium Foundation. All rights reserved.
 * Use of this source code is governed by a BSD-style license which is detailed in the
 * LICENSE file present in the project repository where this source code is maintained.
 * Core maintainer: Jiminy Panoz <jiminy.panoz@edrlab.org> 
 * Contributors: 
 * Daniel Weck
 * Hadrien Gardeur
 * Innovimax
 * L. Le Meur
 * Mickaël Menu
 * k_taka
 */

@namespace url("http://www.w3.org/1999/xhtml");

@namespace epub url("http://www.idpf.org/2007/ops");

@namespace m url("http://www.w3.org/1998/Math/MathML");

@namespace svg url("http://www.w3.org/2000/svg");

@-ms-viewport{
  width:device-width;
}

@viewport{
  width:device-width;
  zoom:1;
}

:root{

  --RS__sans-serif-ja-v:'Hiragino Sans', 'Hiragino Kaku Gothic ProN', 'Hiragino Kaku Gothic Pro', 'ヒラギノ角ゴ W3', 'YuGothic', 'Yu Gothic Medium', 'BIZ UDGothic', 'Yu Gothic', 'ＭＳゴシック', 'MS Gothic', sans-serif;

  --RS__serif-ja-v:'Hiragino Mincho ProN', 'Hiragino Mincho Pro', 'YuMincho', 'BIZ UDMincho', 'Yu Mincho', 'ＭＳ明朝', 'MS Mincho', serif;

  --RS__sans-serif-ja:'Hiragino Sans', 'Hiragino Kaku Gothic ProN', 'Hiragino Kaku Gothic Pro', 'ヒラギノ角ゴ W3', 'YuGothic', 'Yu Gothic Medium', 'BIZ UDPGothic', 'Yu Gothic', 'ＭＳ Ｐゴシック', 'MS PGothic', sans-serif;

  --RS__serif-ja:'Hiragino Mincho ProN', 'Hiragino Mincho Pro', 'YuMincho', 'BIZ UDPMincho', 'Yu Mincho', 'ＭＳ Ｐ明朝', 'MS PMincho', serif;

  --RS__monospaceTf:ui-monospace, 'Andale Mono', 'Cascadia Code', 'Source Code Pro', Menlo, Consolas, 'DejaVu Sans Mono', monospace;

  --RS__humanistTf:Seravek, Calibri, 'Gill Sans Nova', Roboto, Ubuntu, 'DejaVu Sans', source-sans-pro, sans-serif;

  --RS__sansTf:-ui-sans-serif, -apple-system, system-ui, BlinkMacSystemFont, 'Segoe UI Variable', 'Segoe UI', Inter, Roboto, 'Helvetica Neue', 'Arial Nova', 'Liberation Sans', Arial, sans-serif;

  --RS__modernTf:Athelas, Constantia, Charter, 'Bitstream Charter', Cambria, 'Georgia Pro', Georgia, serif;

  --RS__oldStyleTf:'Iowan Old Style', Sitka, 'Sitka Text', Palatino, 'Book Antiqua', 'URW Palladio L', P052, serif;

  --RS__zh-HK-lineHeightCompensation:1.167;

  --RS__zh-HK-baseFontFamily:'方體', 'PingFang HK', '方體', 'PingFang TC', '黑體', 'Heiti TC', 'Microsoft JhengHei UI', 'Microsoft JhengHei', Roboto, Noto, 'Noto Sans CJK TC', sans-serif;

  --RS__zh-TW-lineHeightCompensation:1.167;

  --RS__zh-TW-baseFontFamily:'方體', 'PingFang TC', '黑體', 'Heiti TC', 'Microsoft JhengHei UI', 'Microsoft JhengHei', Roboto, Noto, 'Noto Sans CJK TC', sans-serif;

  --RS__zh-Hant-lineHeightCompensation:1.167;

  --RS__zh-Hant-baseFontFamily:'方體', 'PingFang TC', '黑體', 'Heiti TC', 'Microsoft JhengHei UI', 'Microsoft JhengHei', Roboto, Noto, 'Noto Sans CJK TC', sans-serif;

  --RS__zh-lineHeightCompensation:1.167;

  --RS__zh-baseFontFamily:'方体', 'PingFang SC', '黑体', 'Heiti SC', 'Microsoft JhengHei UI', 'Microsoft JhengHei', Roboto, Noto, 'Noto Sans CJK SC', sans-serif;

  --RS__th-lineHeightCompensation:1.067;

  --RS__th-baseFontFamily:Thonburi, 'Leelawadee UI', 'Cordia New', Roboto, Noto, 'Noto Sans Thai', sans-serif;

  --RS__te-baseFontFamily:'Kohinoor Telugu', 'Telugu Sangam MN', 'Nirmala UI', Gautami, Roboto, Noto, 'Noto Sans Telugu', sans-serif;

  --RS__ta-lineHeightCompensation:1.067;

  --RS__ta-baseFontFamily:'Tamil Sangam MN', 'Nirmala UI', Latha, Roboto, Noto, 'Noto Sans Tamil', sans-serif;

  --RS__si-lineHeightCompensation:1.167;

  --RS__si-baseFontFamily:'Sinhala Sangam MN', 'Nirmala UI', 'Iskoola Pota', Roboto, Noto, 'Noto Sans Sinhala', sans-serif;

  --RS__pa-lineHeightCompensation:1.1;

  --RS__pa-baseFontFamily:'Gurmukhi MN', 'Nirmala UI', Kartika, Roboto, Noto, 'Noto Sans Gurmukhi', sans-serif;

  --RS__or-lineHeightCompensation:1.167;

  --RS__or-baseFontFamily:'Oriya Sangam MN', 'Nirmala UI', Kalinga, Roboto, Noto, 'Noto Sans Oriya', sans-serif;

  --RS__ml-lineHeightCompensation:1.067;

  --RS__ml-baseFontFamily:'Malayalam Sangam MN', 'Nirmala UI', Kartika, Roboto, Noto, 'Noto Sans Malayalam', sans-serif;

  --RS__lo-baseFontFamily:'Lao Sangam MN', 'Leelawadee UI', 'Lao UI', Roboto, Noto, 'Noto Sans Lao', sans-serif;

  --RS__ko-lineHeightCompensation:1.167;

  --RS__ko-baseFontFamily:'Nanum Gothic', 'Apple SD Gothic Neo', 'Malgun Gothic', Roboto, Noto, 'Noto Sans CJK KR', sans-serif;

  --RS__kn-lineHeightCompensation:1.1;

  --RS__kn-baseFontFamily:'Kannada Sangam MN', 'Nirmala UI', Tunga, Roboto, Noto, 'Noto Sans Kannada', sans-serif;

  --RS__km-lineHeightCompensation:1.067;

  --RS__km-baseFontFamily:'Khmer Sangam MN', 'Leelawadee UI', 'Khmer UI', Roboto, Noto, 'Noto Sans Khmer', sans-serif;

  --RS__ja-lineHeightCompensation:1.167;

  --RS__ja-baseFontFamily:YuGothic, 'Hiragino Maru Gothic ProN', 'Hiragino Sans', 'Yu Gothic UI', 'Meiryo UI', 'MS Gothic', Roboto, Noto, 'Noto Sans CJK JP', sans-serif;

  --RS__iu-baseFontFamily:'Euphemia UCAS', Euphemia, Roboto, Noto, 'Noto Sans Canadian Aboriginal', sans-serif;

  --RS__hy-baseFontFamily:Mshtakan, Sylfaen, Roboto, Noto, 'Noto Serif Armenian', serif;

  --RS__hi-lineHeightCompensation:1.1;

  --RS__hi-baseFontFamily:'Kohinoor Devanagari', 'Devanagari Sangam MN', Kokila, 'Nirmala UI', Roboto, Noto, 'Noto Sans Devanagari', sans-serif;

  --RS__he-lineHeightCompensation:1.1;

  --RS__he-baseFontFamily:'New Peninim MT', 'Arial Hebrew', Gisha, 'Times New Roman', Roboto, Noto, 'Noto Sans Hebrew', sans-serif;

  --RS__gu-lineHeightCompensation:1.167;

  --RS__gu-baseFontFamily:'Gujarati Sangam MN', 'Nirmala UI', Shruti, Roboto, Noto, 'Noto Sans Gujarati', sans-serif;

  --RS__fa-baseFontFamily:'Geeza Pro', 'Arabic Typesetting', Roboto, Noto, 'Noto Naskh Arabic', 'Times New Roman', serif;

  --RS__chr-lineHeightCompensation:1.167;

  --RS__chr-baseFontFamily:'Plantagenet Cherokee', Roboto, Noto, 'Noto Sans Cherokee';

  --RS__bo-baseFontFamily:Kailasa, 'Microsoft Himalaya', Roboto, Noto, 'Noto Sans Tibetan', sans-serif;

  --RS__bn-lineHeightCompensation:1.067;

  --RS__bn-baseFontFamily:'Kohinoor Bangla', 'Bangla Sangam MN', Vrinda, Roboto, Noto, 'Noto Sans Bengali', sans-serif;

  --RS__ar-baseFontFamily:'Geeza Pro', 'Arabic Typesetting', Roboto, Noto, 'Noto Naskh Arabic', 'Times New Roman', serif;

  --RS__am-lineHeightCompensation:1.167;

  --RS__am-baseFontFamily:Kefa, Nyala, Roboto, Noto, 'Noto Sans Ethiopic', serif;

  --RS__latin-lineHeightCompensation:1;

  --RS__latin-baseFontFamily:var(--RS__oldStyleTf);
  --RS__baseFontFamily:var(--RS__latin-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__latin-lineHeightCompensation);
  --RS__baseLineHeight:calc(1.5 * var(--RS__lineHeightCompensation));

  --RS__selectionTextColor:inherit;

  --RS__selectionBackgroundColor:#b4d8fe;

  --RS__visitedColor:#551A8B;

  --RS__linkColor:#0000EE;

  --RS__textColor:#121212;

  --RS__backgroundColor:#FFFFFF;
  color:var(--RS__textColor) !important;

  background-color:var(--RS__backgroundColor) !important;
}

::-moz-selection{
  color:var(--RS__selectionTextColor);
  background-color:var(--RS__selectionBackgroundColor);
}

::selection{
  color:var(--RS__selectionTextColor);
  background-color:var(--RS__selectionBackgroundColor);
}

html{
  font-family:var(--RS__baseFontFamily);
  line-height:1.6;
  line-height:var(--RS__baseLineHeight);
  text-rendering:optimizelegibility;
}

h1, h2, h3{
  line-height:normal;
}

:lang(ja),
:lang(zh),
:lang(ko){
  word-wrap:break-word;
  -webkit-line-break:strict;
  -epub-line-break:strict;
  line-break:strict;
}

math{
  font-family:"Latin Modern Math", "STIX Two Math", "XITS Math", "STIX Math", "Libertinus Math", "TeX Gyre Termes Math", "TeX Gyre Bonum Math", "TeX Gyre Schola", "DejaVu Math TeX Gyre", "TeX Gyre Pagella Math", "Asana Math", "Cambria Math", "Lucida Bright Math", "Minion Math", STIXGeneral, STIXSizeOneSym, Symbol, "Times New Roman", serif;
}

:lang(am){
  --RS__baseFontFamily:var(--RS__am-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__am-lineHeightCompensation);
}

:lang(ar){
  --RS__baseFontFamily:var(--RS__ar-baseFontFamily);
}

:lang(bn){
  --RS__baseFontFamily:var(--RS__bn-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__bn-lineHeightCompensation);
}

:lang(bo){
  --RS__baseFontFamily:var(--RS__bo-baseFontFamily);
}

:lang(chr){
  --RS__baseFontFamily:var(--RS__chr-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__chr-lineHeightCompensation);
}

:lang(fa){
  --RS__baseFontFamily:var(--RS__fa-baseFontFamily);
}

:lang(gu){
  --RS__baseFontFamily:var(--RS__gu-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__gu-lineHeightCompensation);
}

:lang(he){
  --RS__baseFontFamily:var(--RS__he-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__he-lineHeightCompensation);
}

:lang(hi){
  --RS__baseFontFamily:var(--RS__hi-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__hi-lineHeightCompensation);
}

:lang(hy){
  --RS__baseFontFamily:var(--RS__hy-baseFontFamily);
}

:lang(iu){
  --RS__baseFontFamily:var(--RS__iu-baseFontFamily);
}

:lang(ja){
  --RS__baseFontFamily:var(--RS__ja-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__ja-lineHeightCompensation);
}

:lang(km){
  --RS__baseFontFamily:var(--RS__km-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__km-lineHeightCompensation);
}

:lang(kn){
  --RS__baseFontFamily:var(--RS__kn-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__kn-lineHeightCompensation);
}

:lang(ko){
  --RS__baseFontFamily:var(--RS__ko-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__ko-lineHeightCompensation);
}

:lang(lo){
  --RS__baseFontFamily:var(--RS__lo-baseFontFamily);
}

:lang(ml){
  --RS__baseFontFamily:var(--RS__ml-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__ml-lineHeightCompensation);
}

:lang(or){
  --RS__baseFontFamily:var(--RS__or-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__or-lineHeightCompensation);
}

:lang(pa){
  --RS__baseFontFamily:var(--RS__pa-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__pa-lineHeightCompensation);
}

:lang(si){
  --RS__baseFontFamily:var(--RS__si-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__si-lineHeightCompensation);
}

:lang(ta){
  --RS__baseFontFamily:var(--RS__ta-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__ta-lineHeightCompensation);
}

:lang(te){
  --RS__baseFontFamily:var(--RS__te-baseFontFamily);
}

:lang(th){
  --RS__baseFontFamily:var(--RS__th-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__th-lineHeightCompensation);
}

:lang(zh){
  --RS__baseFontFamily:var(--RS__zh-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__zh-lineHeightCompensation);
}

:lang(zh-Hant){
  --RS__baseFontFamily:var(--RS__zh-Hant-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__zh-Hant-lineHeightCompensation);
}

:lang(zh-TW){
  --RS__baseFontFamily:var(--RS__zh-TW-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__zh-TW-lineHeightCompensation);
}

:lang(zh-HK){
  --RS__baseFontFamily:var(--RS__zh-HK-baseFontFamily);
  --RS__lineHeightCompensation:var(--RS__zh-HK-lineHeightCompensation);
}

body{
  widows:2;
  orphans:2;
}

figcaption, th, td{
  widows:1;
  orphans:1;
}

h2, h3, h4, h5, h6, dt,
hr, caption{
  -webkit-column-break-after:avoid;
  page-break-after:avoid;
  break-after:avoid;
}

h1, h2, h3, h4, h5, h6, dt,
figure, tr{
  -webkit-column-break-inside:avoid;
  page-break-inside:avoid;
  break-inside:avoid;
}

body{
  -webkit-hyphenate-character:"\\002D";
  -moz-hyphenate-character:"\\002D";
  -ms-hyphenate-character:"\\002D";
  hyphenate-character:"\\002D";
  -webkit-hyphenate-limit-lines:3;
  -ms-hyphenate-limit-lines:3;
  hyphenate-limit-lines:3;
}

h1, h2, h3, h4, h5, h6, dt,
figcaption, pre, caption, address,
center, code, var{
  -ms-hyphens:none;
  -moz-hyphens:none;
  -webkit-hyphens:none;
  -epub-hyphens:none;
  hyphens:none;
}

body{
  font-variant-numeric:oldstyle-nums proportional-nums;
}

:lang(ja) body,
:lang(zh) body,
:lang(ko) body{
  font-variant-numeric:lining-nums proportional-nums;
}

h1, h2, h3, h4, h5, h6, dt{
  font-variant-numeric:lining-nums proportional-nums;
}

table{
  font-variant-numeric:lining-nums tabular-nums;
}

code, var{
  font-variant-ligatures:none;
  font-variant-numeric:lining-nums tabular-nums slashed-zero;
}

rt{
  font-variant-east-asian:ruby;
}

:lang(ar){
  font-variant-ligatures:common-ligatures;
}

:lang(ko){
  font-kerning:normal;
}

hr{
  color:inherit;
  border-color:currentcolor;
}

table, th, td{
  border-color:currentcolor;
}

figure, blockquote{
  margin:1em 5%;
}

ul, ol{
  padding-left:5%;
}

dd{
  margin-left:5%;
}

pre{
  white-space:pre-wrap;
  -ms-tab-size:2;
  -moz-tab-size:2;
  -webkit-tab-size:2;
  tab-size:2;
}

abbr[title], acronym[title]{
  text-decoration:dotted underline;
}

nobr wbr{
  white-space:normal;
}

ruby > rt, ruby > rp{
  -webkit-user-select:none;
  -moz-user-select:none;
  -ms-user-select:none;
  user-select:none;
}

*:lang(ja):not(:lang(ja-Latn)):not(:lang(ja-Cyrl)),
*:lang(zh):not(:lang(zh-Latn)):not(:lang(zh-Cyrl)),
*:lang(ko):not(:lang(ko-Latn)):not(:lang(ko-Cyrl)),
:lang(ja):not(:lang(ja-Latn)):not(:lang(ja-Cyrl)) cite, 
:lang(ja):not(:lang(ja-Latn)):not(:lang(ja-Cyrl)) dfn, 
:lang(ja):not(:lang(ja-Latn)):not(:lang(ja-Cyrl)) em, 
:lang(ja):not(:lang(ja-Latn)):not(:lang(ja-Cyrl)) i,
:lang(zh):not(:lang(zh-Latn)):not(:lang(zh-Cyrl)) cite, 
:lang(zh):not(:lang(zh-Latn)):not(:lang(zh-Cyrl)) dfn, 
:lang(zh):not(:lang(zh-Latn)):not(:lang(zh-Cyrl)) em, 
:lang(zh):not(:lang(zh-Latn)):not(:lang(zh-Cyrl)) i,
:lang(ko):not(:lang(ko-Latn)):not(:lang(ko-Cyrl)) cite, 
:lang(ko):not(:lang(ko-Latn)):not(:lang(ko-Cyrl)) dfn, 
:lang(ko):not(:lang(ko-Latn)):not(:lang(ko-Cyrl)) em, 
:lang(ko):not(:lang(ko-Latn)):not(:lang(ko-Cyrl)) i{
  font-style:normal;
}

:lang(ja) a,
:lang(zh) a,
:lang(ko) a{
  text-decoration:none;
}

:root{
  --RS__maxMediaWidth:100%;
  --RS__maxMediaHeight:95vh;
  --RS__boxSizingMedia:border-box;
  --RS__boxSizingTable:border-box;
}

a, a span, span a, h1, h2, h3, h4, h5, h6{
  word-wrap:break-word;
}

div{
  max-width:var(--RS__maxMediaWidth);
}

img, svg|svg, video{
  object-fit:contain;

  width:auto;
  height:auto;
  max-width:var(--RS__maxMediaWidth);
  max-height:var(--RS__maxMediaHeight) !important;
  box-sizing:var(--RS__boxSizingMedia);
  -webkit-column-break-inside:avoid;
  page-break-inside:avoid;
  break-inside:avoid;
}

@supports (zoom: 1) and (not ((-webkit-column-axis: horizontal) and (-webkit-column-progression: normal))){

  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] img,
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] svg|svg,
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] video{
    zoom:calc(100% / var(--USER__fontSize));
  }
}

audio{
    max-width:100%;
    -webkit-column-break-inside:avoid;
    page-break-inside:avoid;
    break-inside:avoid;
  }

table{
  max-width:var(--RS__maxMediaWidth);
  box-sizing:var(--RS__boxSizingTable);
}`})),Pd=r({default:()=>Fd}),Fd,Id=n((()=>{Fd=`/*!
 * Readium CSS v.2.0.5
 * Copyright (c) 2017–2026. Readium Foundation. All rights reserved.
 * Use of this source code is governed by a BSD-style license which is detailed in the
 * LICENSE file present in the project repository where this source code is maintained.
 * Core maintainer: Jiminy Panoz <jiminy.panoz@edrlab.org> 
 * Contributors: 
 * Daniel Weck
 * Hadrien Gardeur
 * Innovimax
 * L. Le Meur
 * Mickaël Menu
 * k_taka
 */

@namespace url("http://www.w3.org/1999/xhtml");

@namespace epub url("http://www.idpf.org/2007/ops");

@namespace m url("http://www.w3.org/1998/Math/MathML");

@namespace svg url("http://www.w3.org/2000/svg");

:root{
  --RS__compFontFamily:var(--RS__baseFontFamily);
  --RS__codeFontFamily:var(--RS__monospaceTf);

  --RS__typeScale:1.125;
  --RS__baseFontSize:100%;

  --RS__flowSpacing:1.5rem;
  --RS__paraSpacing:0;
  --RS__paraIndent:1em;

  --RS__linkColor:#0000EE;
  --RS__visitedColor:#551A8B;

  --RS__primaryColor:;
  --RS__secondaryColor:;
}

body{
  font-size:var(--RS__baseFontSize);
}

h1, h2, h3, h4, h5, h6{
  font-family:var(--RS__compFontFamily);
}

blockquote, figure, p, pre,
aside, footer, form, hr{
  margin-top:var(--RS__flowSpacing);
  margin-bottom:var(--RS__flowSpacing);
}

p{
  margin-top:var(--RS__paraSpacing);
  margin-bottom:var(--RS__paraSpacing);
  text-indent:var(--RS__paraIndent);
}

h1 + p, h2 + p, h3 + p, h4 + p, h5 + p, h6 + p,
hr + p{
  text-indent:0;
}

pre{
  font-family:var(--RS__codeFontFamily);
}

code, kbd, samp, tt{
  font-family:var(--RS__codeFontFamily);
}

sub, sup{
  position:relative;
  font-size:67.5%;
  line-height:1;
}

sub{
  bottom:-0.2ex;
}

sup{
  bottom:0;
}

:link{
  color:var(--RS__linkColor);
}

:visited{
  color:var(--RS__visitedColor);
}

h1{
  margin-top:calc(var(--RS__flowSpacing) * 2);
  margin-bottom:calc(var(--RS__flowSpacing) * 2);
  font-size:calc(((1em * var(--RS__typeScale)) * var(--RS__typeScale)) * var(--RS__typeScale));
}

h2{
  margin-top:calc(var(--RS__flowSpacing) * 2);
  margin-bottom:var(--RS__flowSpacing);
  font-size:calc((1em * var(--RS__typeScale)) * var(--RS__typeScale));
}

h3{
  margin-top:var(--RS__flowSpacing);
  margin-bottom:var(--RS__flowSpacing);
  font-size:calc(1em * var(--RS__typeScale));
}

h4{
  margin-top:var(--RS__flowSpacing);
  margin-bottom:var(--RS__flowSpacing);
  font-size:1em;
}

h5{
  margin-top:var(--RS__flowSpacing);
  margin-bottom:var(--RS__flowSpacing);
  font-size:1em;
  font-variant:small-caps;
}

h6{
  margin-top:var(--RS__flowSpacing);
  margin-bottom:0;
  font-size:1em;
  text-transform:lowercase;
  font-variant:small-caps;
}

dl, ol, ul{
  margin-top:var(--RS__flowSpacing);
  margin-bottom:var(--RS__flowSpacing);
}

table{
  margin:var(--RS__flowSpacing) 0;
  border:1px solid currentcolor;
  border-collapse:collapse;
  empty-cells:show;
}

thead, tbody, tfoot, table > tr{
  vertical-align:top;
}

th{
  text-align:left;
}

th, td{
  padding:4px;
  border:1px solid currentcolor;
}`})),Ld=r({default:()=>Rd}),Rd,zd=n((()=>{Rd=`/*!
 * Readium CSS v.2.0.5
 * Copyright (c) 2017–2026. Readium Foundation. All rights reserved.
 * Use of this source code is governed by a BSD-style license which is detailed in the
 * LICENSE file present in the project repository where this source code is maintained.
 * Core maintainer: Jiminy Panoz <jiminy.panoz@edrlab.org> 
 * Contributors: 
 * Daniel Weck
 * Hadrien Gardeur
 * Innovimax
 * L. Le Meur
 * Mickaël Menu
 * k_taka
 */

@namespace url("http://www.w3.org/1999/xhtml");

@namespace epub url("http://www.idpf.org/2007/ops");

@namespace m url("http://www.w3.org/1998/Math/MathML");

@namespace svg url("http://www.w3.org/2000/svg");

:root{

  --RS__viewportWidth:100%;

  --RS__pageGutter:0;

  --RS__defaultLineLength:100%;

  --RS__colGap:0;

  --RS__colCount:1;

  --RS__colWidth:100vw;
}

@page{
  margin:0 !important;
}

:root{
  position:relative;

  -webkit-column-width:var(--RS__colWidth);
  -moz-column-width:var(--RS__colWidth);
  column-width:var(--RS__colWidth);
  -webkit-column-count:var(--RS__colCount);
  -moz-column-count:var(--RS__colCount);
  column-count:var(--RS__colCount);

  -webkit-column-gap:var(--RS__colGap);
  -moz-column-gap:var(--RS__colGap);
  column-gap:var(--RS__colGap);
  -moz-column-fill:auto;
  column-fill:auto;
  width:var(--RS__viewportWidth);
  height:100vh;
  max-width:var(--RS__viewportWidth);
  max-height:100vh;
  min-width:var(--RS__viewportWidth);
  min-height:100vh;
  padding:0 !important;
  margin:0 !important;
  font-size:1rem !important;
  box-sizing:border-box;
  -webkit-touch-callout:none;
}

body{
  width:100%;
  max-width:var(--RS__defaultLineLength) !important;
  margin:0 auto !important;
  box-sizing:border-box;
}

:root:not([style*="readium-scroll-on"]) body{
  padding:0 var(--RS__pageGutter) !important;
}

:root:not([style*="readium-noOverflow-on"]) body{
  overflow:hidden;
}

@supports (overflow: clip){

   :root:not([style*="readium-noOverflow-on"]){
      overflow:clip;
   }

   :root:not([style*="readium-noOverflow-on"]) body{
      overflow:clip;
      overflow-clip-margin:content-box;
   }
}

:root[style*="readium-scroll-on"]{
  -webkit-columns:auto auto !important;
  -moz-columns:auto auto !important;
  columns:auto auto !important;
  width:auto !important;
  height:auto !important;
  max-width:none !important;
  max-height:none !important;
  min-width:0 !important;
  min-height:0 !important;
}

:root[style*="readium-scroll-on"] body{
  max-width:var(--RS__defaultLineLength) !important;
  box-sizing:border-box !important;
}

:root[style*="readium-scroll-on"]:not([style*="readium-noOverflow-on"]) body{
  overflow:auto;
}

@supports (overflow: clip){

  :root[style*="readium-scroll-on"]:not([style*="readium-noOverflow-on"]){
     overflow:auto;
  }

  :root[style*="readium-scroll-on"]:not([style*="readium-noOverflow-on"]) body{
     overflow:clip;
  }
}

:root[style*="readium-scroll-on"][style*="--RS__scrollPaddingTop"] body{
  padding-top:var(--RS__scrollPaddingTop) !important;
}

:root[style*="readium-scroll-on"][style*="--RS__scrollPaddingBottom"] body{
  padding-bottom:var(--RS__scrollPaddingBottom) !important;
}

:root[style*="readium-scroll-on"][style*="--RS__scrollPaddingLeft"] body{
  padding-left:var(--RS__scrollPaddingLeft) !important;
}

:root[style*="readium-scroll-on"][style*="--RS__scrollPaddingRight"] body{
  padding-right:var(--RS__scrollPaddingRight) !important;
}

:root[style*="--USER__backgroundColor"]{
  background-color:var(--USER__backgroundColor) !important;
}

:root[style*="--USER__backgroundColor"] *{
  background-color:transparent !important;
}

:root[style*="--USER__textColor"]{
  color:var(--USER__textColor) !important;
}

:root[style*="--USER__textColor"] *:not(a){
  color:inherit !important;
  background-color:transparent !important;
  border-color:currentcolor !important;
}

:root[style*="--USER__textColor"] svg text{
  fill:currentcolor !important;
  stroke:none !important;
}

:root[style*="--USER__linkColor"] a:link,
:root[style*="--USER__linkColor"] a:link *{
  color:var(--USER__linkColor) !important;
}

:root[style*="--USER__visitedColor"] a:visited,
:root[style*="--USER__visitedColor"] a:visited *{
  color:var(--USER__visitedColor) !important;
}

:root[style*="--USER__selectionBackgroundColor"][style*="--USER__selectionTextColor"] ::-moz-selection{
  color:var(--USER__selectionTextColor) !important;
  background-color:var(--USER__selectionBackgroundColor) !important;
}

:root[style*="--USER__selectionBackgroundColor"][style*="--USER__selectionTextColor"] ::selection{
  color:var(--USER__selectionTextColor) !important;
  background-color:var(--USER__selectionBackgroundColor) !important;
}

:root[style*="--USER__colCount"]{
  -webkit-column-count:var(--USER__colCount);
  -moz-column-count:var(--USER__colCount);
  column-count:var(--USER__colCount);

  --RS__colWidth:auto;
}

:root[style*="--USER__colCount: 0"],
:root[style*="--USER__colCount:0"]{
  -webkit-column-count:1;
  -moz-column-count:1;
  column-count:1;
}

:root[style*="--USER__colCount: 0"],
:root[style*="--USER__colCount:0"],
:root[style*="--USER__colCount: 1"],
:root[style*="--USER__colCount:1"]{
  --RS__colWidth:100vw;
}

:root[style*="--USER__lineLength"] body{
    max-width:var(--USER__lineLength) !important;
  }

:root[style*="--USER__textAlign"]{
  text-align:var(--USER__textAlign);
}

:root[style*="--USER__textAlign"] body,
:root[style*="--USER__textAlign"] p:not(
  blockquote p,
  figcaption p,
  header p,
  hgroup p,
  :root[style*="readium-experimentalHeaderFiltering-on"] p[class*="title"],
  :root[style*="readium-experimentalHeaderFiltering-on"] div:has(+ *) > h1 + p,
  :root[style*="readium-experimentalHeaderFiltering-on"] div:has(+ *) > p:has(+ h1)
),
:root[style*="--USER__textAlign"] li,
:root[style*="--USER__textAlign"] dd{
  text-align:var(--USER__textAlign) !important;
  -moz-text-align-last:auto !important;
  -epub-text-align-last:auto !important;
  text-align-last:auto !important;
}

:root[style*="--USER__bodyHyphens"]{
  -webkit-hyphens:var(--USER__bodyHyphens) !important;
  -moz-hyphens:var(--USER__bodyHyphens) !important;
  -ms-hyphens:var(--USER__bodyHyphens) !important;
  -epub-hyphens:var(--USER__bodyHyphens) !important;
  hyphens:var(--USER__bodyHyphens) !important;
}

:root[style*="--USER__bodyHyphens"] body,
:root[style*="--USER__bodyHyphens"] p,
:root[style*="--USER__bodyHyphens"] li,
:root[style*="--USER__bodyHyphens"] div,
:root[style*="--USER__bodyHyphens"] dd{
  -webkit-hyphens:var(--USER__bodyHyphens) !important;
  -moz-hyphens:var(--USER__bodyHyphens) !important;
  -ms-hyphens:var(--USER__bodyHyphens) !important;
  -epub-hyphens:var(--USER__bodyHyphens) !important;
  hyphens:var(--USER__bodyHyphens) !important;
}

:root[style*="--USER__fontFamily"]{
  font-family:var(--USER__fontFamily) !important;
}

:root[style*="--USER__fontFamily"] *{
  font-family:revert !important;
}

:root[style*="readium-a11y-on"]{
  font-style:normal !important;
  font-weight:normal !important;
}

:root[style*="readium-a11y-on"] body *:not(code):not(var):not(kbd):not(samp){
  font-family:inherit !important;
  font-style:inherit !important;
  font-weight:inherit !important;
}

:root[style*="readium-a11y-on"] body *:not(a){
  text-decoration:none !important;
}

:root[style*="readium-a11y-on"] body *{
  font-variant-caps:normal !important;
  font-variant-numeric:normal !important;
  font-variant-position:normal !important;
}

:root[style*="readium-a11y-on"] sup,
:root[style*="readium-a11y-on"] sub{
  font-size:1rem !important;
  vertical-align:baseline !important;
}

:root:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] body{
  zoom:var(--USER__fontSize) !important;
}

:root:not([style*="readium-deprecatedFontSize-on"])[style*="readium-iOSPatch-on"][style*="--USER__fontSize"] body{
  -webkit-text-size-adjust:var(--USER__fontSize) !important;
}

@supports selector(figure:has(> img)){

  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] figure:has(> img),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] figure:has(> video),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] figure:has(> svg),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] figure:has(> canvas),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] figure:has(> iframe),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] figure:has(> audio),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] div:has(> img:only-child),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] div:has(> video:only-child),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] div:has(> svg:only-child),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] div:has(> canvas:only-child),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] div:has(> iframe:only-child),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] div:has(> audio:only-child),
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] table{
    zoom:calc(100% / var(--USER__fontSize)) !important;
  }

  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] figcaption,
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] caption,
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] td,
  :root[style*="readium-experimentalZoom-on"]:not([style*="readium-deprecatedFontSize-on"]):not([style*="readium-iOSPatch-on"])[style*="--USER__fontSize"] th{
    zoom:var(--USER__fontSize) !important;
  }
}

@supports not (zoom: 1){

  :root[style*="--USER__fontSize"]{
    font-size:var(--USER__fontSize) !important;
  }
}

:root[style*="readium-deprecatedFontSize-on"][style*="--USER__fontSize"]{
  font-size:var(--USER__fontSize) !important;
}

:root[style*="--USER__lineHeight"]{
  line-height:var(--USER__lineHeight) !important;
}

:root[style*="--USER__lineHeight"] body,
:root[style*="--USER__lineHeight"] p,
:root[style*="--USER__lineHeight"] li,
:root[style*="--USER__lineHeight"] div{
  line-height:var(--USER__lineHeight) !important;
}

:root[style*="--USER__paraSpacing"] p{
  margin-top:var(--USER__paraSpacing) !important;
  margin-bottom:var(--USER__paraSpacing) !important;
}

:root[style*="--USER__paraIndent"] p:not(
  blockquote p,
  figcaption p,
  header p,
  hgroup p,
  :root[style*="readium-experimentalHeaderFiltering-on"] p[class*="title"],
  :root[style*="readium-experimentalHeaderFiltering-on"] div:has(+ *) > h1 + p,
  :root[style*="readium-experimentalHeaderFiltering-on"] div:has(+ *) > p:has(+ h1)
){
  text-indent:var(--USER__paraIndent) !important;
}

:root[style*="--USER__paraIndent"] p *{
  text-indent:0 !important;
}

:root[style*="--USER__wordSpacing"] h1,
:root[style*="--USER__wordSpacing"] h2,
:root[style*="--USER__wordSpacing"] h3,
:root[style*="--USER__wordSpacing"] h4,
:root[style*="--USER__wordSpacing"] h5,
:root[style*="--USER__wordSpacing"] h6,
:root[style*="--USER__wordSpacing"] p,
:root[style*="--USER__wordSpacing"] li,
:root[style*="--USER__wordSpacing"] div,
:root[style*="--USER__wordSpacing"] dt,
:root[style*="--USER__wordSpacing"] dd{
  word-spacing:var(--USER__wordSpacing) !important;
}

:root[style*="--USER__letterSpacing"] h1,
:root[style*="--USER__letterSpacing"] h2,
:root[style*="--USER__letterSpacing"] h3,
:root[style*="--USER__letterSpacing"] h4,
:root[style*="--USER__letterSpacing"] h5,
:root[style*="--USER__letterSpacing"] h6,
:root[style*="--USER__letterSpacing"] p,
:root[style*="--USER__letterSpacing"] li,
:root[style*="--USER__letterSpacing"] div,
:root[style*="--USER__letterSpacing"] dt,
:root[style*="--USER__letterSpacing"] dd{
  letter-spacing:var(--USER__letterSpacing) !important;
  font-variant:none !important;
}

:root[style*="--USER__ligatures"]{
  font-variant-ligatures:var(--USER__ligatures) !important;
}

:root[style*="--USER__ligatures"] *{
  font-variant-ligatures:inherit !important;
}

:root[style*="--USER__fontWeight"] body{
  font-weight:var(--USER__fontWeight) !important;
}

:root[style*="--USER__fontWeight"] b,
:root[style*="--USER__fontWeight"] strong{
  font-weight:bolder;
}

:root[style*="--USER__fontWidth"] body{
  font-stretch:var(--USER__fontWidth) !important;
}

:root[style*="--USER__fontOpticalSizing"] body{
  font-optical-sizing:var(--USER__fontOpticalSizing) !important;
}

:root[style*="readium-blend-on"] svg,
:root[style*="readium-blend-on"] img{
  background-color:transparent !important;
  mix-blend-mode:multiply !important;
}

:root[style*="--USER__darkenImages"] img{
  -webkit-filter:brightness(var(--USER__darkenImages)) !important;
  filter:brightness(var(--USER__darkenImages)) !important;
}

:root[style*="readium-darken-on"] img{
  -webkit-filter:brightness(80%) !important;
  filter:brightness(80%) !important;
}

:root[style*="--USER__invertImages"] img{
  -webkit-filter:invert(var(--USER__invertImages)) !important;
  filter:invert(var(--USER__invertImages)) !important;
}

:root[style*="readium-invert-on"] img{
  -webkit-filter:invert(100%) !important;
  filter:invert(100%) !important;
}

:root[style*="--USER__darkenImages"][style*="--USER__invertImages"] img{
  -webkit-filter:brightness(var(--USER__darkenImages)) invert(var(--USER__invertImages)) !important;
  filter:brightness(var(--USER__darkenImages)) invert(var(--USER__invertImages)) !important;
}

:root[style*="readium-darken-on"][style*="--USER__invertImages"] img{
  -webkit-filter:brightness(80%) invert(var(--USER__invertImages)) !important;
  filter:brightness(80%) invert(var(--USER__invertImages)) !important;
}

:root[style*="--USER__darkenImages"][style*="readium-invert-on"] img{
  -webkit-filter:brightness(var(--USER__darkenImages)) invert(100%) !important;
  filter:brightness(var(--USER__darkenImages)) invert(100%) !important;
}

:root[style*="readium-darken-on"][style*="readium-invert-on"] img{
  -webkit-filter:brightness(80%) invert(100%) !important;
  filter:brightness(80%) invert(100%) !important;
}

:root[style*="--USER__invertGaiji"] img[class*="gaiji"]{
  -webkit-filter:invert(var(--USER__invertGaiji)) !important;
  filter:invert(var(--USER__invertGaiji)) !important;
}

:root[style*="readium-invertGaiji-on"] img[class*="gaiji"]{
  -webkit-filter:invert(100%) !important;
  filter:invert(100%) !important;
}

:root[style*="readium-normalize-on"]{
  --USER__typeScale:1.2;
}

:root[style*="readium-normalize-on"] p,
:root[style*="readium-normalize-on"] li,
:root[style*="readium-normalize-on"] div,
:root[style*="readium-normalize-on"] pre,
:root[style*="readium-normalize-on"] dd{
  font-size:1rem !important;
}

:root[style*="readium-normalize-on"] h1{
  font-size:1.75rem !important;
  font-size:calc(((1rem * var(--USER__typeScale)) * var(--USER__typeScale)) * var(--USER__typeScale)) !important;
}

:root[style*="readium-normalize-on"] h2{
  font-size:1.5rem !important;
  font-size:calc((1rem * var(--USER__typeScale)) * var(--USER__typeScale)) !important;
}

:root[style*="readium-normalize-on"] h3{
  font-size:1.25rem !important;
  font-size:calc(1rem * var(--USER__typeScale)) !important;
}

:root[style*="readium-normalize-on"] h4,
:root[style*="readium-normalize-on"] h5,
:root[style*="readium-normalize-on"] h6{
  font-size:1rem !important;
}

:root[style*="readium-normalize-on"] small{
  font-size:smaller !important;
}

:root[style*="readium-normalize-on"] sub,
:root[style*="readium-normalize-on"] sup{
  font-size:67.5% !important;
}

:root[style*="readium-normalize-on"][style*="--USER__typeScale"] h1{
  font-size:calc(((1rem * var(--USER__typeScale)) * var(--USER__typeScale)) * var(--USER__typeScale)) !important;
}

:root[style*="readium-normalize-on"][style*="--USER__typeScale"] h2{
  font-size:calc((1rem * var(--USER__typeScale)) * var(--USER__typeScale)) !important;
}

:root[style*="readium-normalize-on"][style*="--USER__typeScale"] h3{
  font-size:calc(1rem * var(--USER__typeScale)) !important;
}

:root[style*="readium-iPadOSPatch-on"] body{
  -webkit-text-size-adjust:none;
}

:root[style*="readium-iPadOSPatch-on"] p, 
:root[style*="readium-iPadOSPatch-on"] h1, 
:root[style*="readium-iPadOSPatch-on"] h2, 
:root[style*="readium-iPadOSPatch-on"] h3, 
:root[style*="readium-iPadOSPatch-on"] h4, 
:root[style*="readium-iPadOSPatch-on"] h5, 
:root[style*="readium-iPadOSPatch-on"] h6, 
:root[style*="readium-iPadOSPatch-on"] li, 
:root[style*="readium-iPadOSPatch-on"] th, 
:root[style*="readium-iPadOSPatch-on"] td, 
:root[style*="readium-iPadOSPatch-on"] dt, 
:root[style*="readium-iPadOSPatch-on"] dd, 
:root[style*="readium-iPadOSPatch-on"] pre, 
:root[style*="readium-iPadOSPatch-on"] address, 
:root[style*="readium-iPadOSPatch-on"] details, 
:root[style*="readium-iPadOSPatch-on"] summary,
:root[style*="readium-iPadOSPatch-on"] figcaption,
:root[style*="readium-iPadOSPatch-on"] div:not(:has(p, h1, h2, h3, h4, h5, h6, li, th, td, dt, dd, pre, address, aside, details, figcaption, summary)),
:root[style*="readium-iPadOSPatch-on"] aside:not(:has(p, h1, h2, h3, h4, h5, h6, li, th, td, dt, dd, pre, address, aside, details, figcaption, summary)){
  -webkit-text-zoom:reset;
}

:root[style*="readium-iPadOSPatch-on"] abbr, 
:root[style*="readium-iPadOSPatch-on"] b, 
:root[style*="readium-iPadOSPatch-on"] bdi, 
:root[style*="readium-iPadOSPatch-on"] bdo, 
:root[style*="readium-iPadOSPatch-on"] cite, 
:root[style*="readium-iPadOSPatch-on"] code, 
:root[style*="readium-iPadOSPatch-on"] dfn, 
:root[style*="readium-iPadOSPatch-on"] em, 
:root[style*="readium-iPadOSPatch-on"] i, 
:root[style*="readium-iPadOSPatch-on"] kbd, 
:root[style*="readium-iPadOSPatch-on"] mark, 
:root[style*="readium-iPadOSPatch-on"] q, 
:root[style*="readium-iPadOSPatch-on"] rp, 
:root[style*="readium-iPadOSPatch-on"] rt, 
:root[style*="readium-iPadOSPatch-on"] ruby, 
:root[style*="readium-iPadOSPatch-on"] s, 
:root[style*="readium-iPadOSPatch-on"] samp, 
:root[style*="readium-iPadOSPatch-on"] small, 
:root[style*="readium-iPadOSPatch-on"] span, 
:root[style*="readium-iPadOSPatch-on"] strong, 
:root[style*="readium-iPadOSPatch-on"] sub, 
:root[style*="readium-iPadOSPatch-on"] sup, 
:root[style*="readium-iPadOSPatch-on"] time, 
:root[style*="readium-iPadOSPatch-on"] u, 
:root[style*="readium-iPadOSPatch-on"] var{
  -webkit-text-zoom:normal;
}

:root[style*="readium-iPadOSPatch-on"] p:not(:has(b, cite, em, i, q, s, small, span, strong)):first-line{
  -webkit-text-zoom:normal;
}`})),Bd=r({default:()=>Vd}),Vd,Hd=n((()=>{Vd=`/* Readium CSS
   EBPAJ Fonts Patch module

   A stylesheet improving EBPAJ @font-face declarations to cover all platforms

   Repo: https://github.com/readium/css */

/* EBPAJ template only references fonts from MS Windows…
   so we must reference fonts from other platforms
   and override authors’ stylesheets.
   What we do there is keeping their default value and providing fallbacks.

   /!\\ /!\\ /!\\ /!\\ /!\\
   FYI, you might want to load this polyfill only if you find
   one of the following metadata items in the OPF package:
   - version 1:
     <dc:description id="ebpaj-guide">ebpaj-guide-1.0</dc:description>
   - version 1.1:
     <meta property="ebpaj:guide-version">1.1</meta>
*/

/* 
   Hiragino PostScript Font name lists:
   https://www.screen.co.jp/ga_product/sento/support/QA/ss_psname.html
*/

/* 横組み用 (horizontal writing) */

@font-face {
  font-family: "serif-ja";
  src: local("ＭＳ Ｐ明朝"), /* for IE */
      local("MS PMincho"), /* ＭＳ Ｐ明朝 */
      local("HiraMinProN-W3"), local("Hiragino Mincho ProN"), /* ヒラギノ明朝 ProN W3 */
      local("HiraMinPro-W3"), local("Hiragino Mincho Pro"), /* ヒラギノ明朝 Pro W3 */
      local("YuMin-Medium"), local("YuMincho"), /* 游明朝体(macOS) */
      local("Yu Mincho"), /* 游明朝(Windows) */
      local("BIZ UDPMincho"); /* BIZ UDP明朝 */
}

@font-face {
  font-family: "sans-serif-ja";
  src: local("ＭＳ Ｐゴシック"), /* for IE */
       local("MS PGothic"), /* ＭＳ Ｐゴシック */
       local("HiraginoSans-W3"), local("Hiragino Sans"), /* ヒラギノ角ゴシック */
       local("HiraKakuProN-W3"), local("Hiragino Kaku Gothic ProN"), /* ヒラギノ角ゴ ProN W3 */
       local("HiraKakuPro-W3"), local("Hiragino Kaku Gothic Pro"), /* ヒラギノ角ゴ Pro W3 */
       local("ヒラギノ角ゴ W3"), /* for old  Safari */
       local("HiraginoKaku-W3-90msp-RKSJ-H"), /* ヒラギノ角ゴ W3(TrueType) */
       local("YuGothic-Medium"), local("YuGothic"), /* 游ゴシック体(macOS) */
       local("Yu Gothic Medium"), local("Yu Gothic"), /* 游ゴシック(Windows) "Yu Gothic" is a fallback. */
       local("BIZ UDPGothic"); /* BIZ UDPゴシック */
}

/* 縦組み用 (vertical writing) */

@font-face {
  font-family: "serif-ja-v";
  src: local("ＭＳ 明朝"), /* for IE */
       local("MS Mincho"), /* ＭＳ 明朝 */
       local("HiraMinProN-W3"), local("Hiragino Mincho ProN"), /* ヒラギノ明朝 ProN W3 */
       local("HiraMinPro-W3"), local("Hiragino Mincho Pro"), /* ヒラギノ明朝 Pro W3 */
       local("YuMin-Medium"), local("YuMincho"), /* 游明朝体(macOS) */
       local("Yu Mincho"), /* 游明朝(Windows) */
       local("BIZ UDMincho"); /*  BIZ UD明朝 */
}

@font-face {
  font-family: "sans-serif-ja-v";
  src: local("ＭＳ ゴシック"), /* for IE */
       local("MS Gothic"), /* ＭＳ ゴシック */
       local("HiraginoSans-W3"), local("Hiragino Sans"), /* ヒラギノ角ゴシック */
       local("HiraKakuProN-W3"), local("Hiragino Kaku Gothic ProN"), /* ヒラギノ角ゴ ProN W3 */
       local("HiraKakuPro-W3"), local("Hiragino Kaku Gothic Pro"), /* ヒラギノ角ゴ Pro W3 */
       local("ヒラギノ角ゴ W3"), /* for old Safari */
       local("HiraKakuDS-W3-83pv-RKSJ-H"), /* ヒラギノ角ゴ W3(TrueType) */
       local("YuGothic-Medium"), local("YuGothic"), /* 游ゴシック体(macOS) */
       local("Yu Gothic Medium"), local("Yu Gothic"), /* 游ゴシック(Windows)  "Yu Gothic" is a fallback. */
       local("BIZ UDGothic"); /* BIZ UDゴシック */
}`}));async function Ud(e,t){let n=e.effectiveLayout===D.fixed,r=t.filter(e=>e.mediaType.isHTML).map(e=>e.href),i=r.length>0?r:[/\.xhtml$/,/\.html$/],a=[{id:`css-selector-generator`,as:`script`,target:`head`,blob:new Blob([Bl(Ul)],{type:`text/javascript`})},{id:`execution-prevention`,as:`script`,target:`head`,blob:new Blob([Bl(rd)],{type:`text/javascript`}),condition:e=>!!(e.querySelector(`script`)||e.querySelector(`body[onload]:not(body[onload=''])`))}],o=[{id:`onload-proxy`,as:`script`,target:`head`,blob:new Blob([Bl(Gl)],{type:`text/javascript`}),condition:e=>!!(e.querySelector(`script`)||e.querySelector(`body[onload]:not(body[onload=''])`))}];if(!n){let t=Qc(e),n,r,i;switch(t){case`rtl`:{let[e,t,a]=await Promise.all([$(()=>Promise.resolve().then(()=>(od(),id)),[]),$(()=>Promise.resolve().then(()=>(ld(),sd)),[]),$(()=>Promise.resolve().then(()=>(fd(),ud)),[])]);n=e.default,r=t.default,i=a.default;break}case`cjk-horizontal`:{let[e,t,a]=await Promise.all([$(()=>Promise.resolve().then(()=>(hd(),pd)),[]),$(()=>Promise.resolve().then(()=>(vd(),gd)),[]),$(()=>Promise.resolve().then(()=>(xd(),yd)),[])]);n=e.default,r=t.default,i=a.default;break}case`cjk-vertical`:case`mongolian-vertical`:{let[e,t,a]=await Promise.all([$(()=>Promise.resolve().then(()=>(wd(),Sd)),[]),$(()=>Promise.resolve().then(()=>(Dd(),Td)),[]),$(()=>Promise.resolve().then(()=>(Ad(),Od)),[])]);n=e.default,r=t.default,i=a.default;break}default:{let[e,t,a]=await Promise.all([$(()=>Promise.resolve().then(()=>(Nd(),jd)),[]),$(()=>Promise.resolve().then(()=>(Id(),Pd)),[]),$(()=>Promise.resolve().then(()=>(zd(),Ld)),[])]);n=e.default,r=t.default,i=a.default;break}}if(a.unshift({id:`readium-css-before`,as:`link`,target:`head`,blob:new Blob([Vl(n)],{type:`text/css`}),rel:`stylesheet`}),o.unshift({id:`readium-css-default`,as:`link`,target:`head`,blob:new Blob([Vl(r)],{type:`text/css`}),rel:`stylesheet`,condition:e=>!(e.querySelector(`link[rel='stylesheet']`)||e.querySelector(`style`)||e.querySelector(`[style]:not([style=''])`))},{id:`readium-css-after`,as:`link`,target:`head`,blob:new Blob([Vl(i)],{type:`text/css`}),rel:`stylesheet`}),(t===`cjk-horizontal`||t===`cjk-vertical`)&&(e.description===`ebpaj-guide-1.0`||e.otherMetadata?.[`ebpaj:guide-version`]!==void 0)){let{default:e}=await $(async()=>{let{default:e}=await Promise.resolve().then(()=>(Hd(),Bd));return{default:e}},[]);o.push({id:`readium-css-ebpaj`,as:`link`,target:`head`,blob:new Blob([Vl(e)],{type:`text/css`}),rel:`stylesheet`})}}return[{resources:i,prepend:a,append:o}]}var Wd=class{constructor(e,t){this.backgroundColor=e.backgroundColor||t.backgroundColor||null,this.blendFilter=typeof e.blendFilter==`boolean`?e.blendFilter:t.blendFilter??null,this.columnCount=e.columnCount===void 0?t.columnCount===void 0?null:t.columnCount:e.columnCount,this.constraint=e.constraint||t.constraint,this.darkenFilter=typeof e.darkenFilter==`boolean`?e.darkenFilter:t.darkenFilter??null,this.deprecatedFontSize=typeof e.deprecatedFontSize==`boolean`?e.deprecatedFontSize:t.deprecatedFontSize??null,this.fontFamily=e.fontFamily||t.fontFamily||null,this.fontSize=e.fontSize===void 0?t.fontSize===void 0?null:t.fontSize:e.fontSize,this.fontSizeNormalize=typeof e.fontSizeNormalize==`boolean`?e.fontSizeNormalize:t.fontSizeNormalize??null,this.fontOpticalSizing=typeof e.fontOpticalSizing==`boolean`?e.fontOpticalSizing:t.fontOpticalSizing??null,this.fontWeight=e.fontWeight===void 0?t.fontWeight===void 0?null:t.fontWeight:e.fontWeight,this.fontWidth=e.fontWidth===void 0?t.fontWidth===void 0?null:t.fontWidth:e.fontWidth,this.hyphens=typeof e.hyphens==`boolean`?e.hyphens:t.hyphens??null,this.invertFilter=typeof e.invertFilter==`boolean`?e.invertFilter:t.invertFilter??null,this.invertGaijiFilter=typeof e.invertGaijiFilter==`boolean`?e.invertGaijiFilter:t.invertGaijiFilter??null,this.iOSPatch=this.deprecatedFontSize||e.iOSPatch===!1?!1:e.iOSPatch===!0?(V.OS.iOS||V.OS.iPadOS)&&V.iOSRequest===`mobile`:t.iOSPatch,this.iPadOSPatch=this.deprecatedFontSize||e.iPadOSPatch===!1?!1:e.iPadOSPatch===!0?V.OS.iPadOS&&V.iOSRequest===`desktop`:t.iPadOSPatch,this.letterSpacing=e.letterSpacing===void 0?t.letterSpacing===void 0?null:t.letterSpacing:e.letterSpacing,this.ligatures=typeof e.ligatures==`boolean`?e.ligatures:t.ligatures??null,this.lineHeight=e.lineHeight===void 0?t.lineHeight===void 0?null:t.lineHeight:e.lineHeight,this.linkColor=e.linkColor||t.linkColor||null,this.maximalLineLength=e.maximalLineLength===null?null:e.maximalLineLength||t.maximalLineLength||null,this.minimalLineLength=e.minimalLineLength===null?null:e.minimalLineLength||t.minimalLineLength||null,this.noRuby=typeof e.noRuby==`boolean`?e.noRuby:t.noRuby??null,this.optimalLineLength=e.optimalLineLength||t.optimalLineLength,this.pageGutter=e.pageGutter===void 0?t.pageGutter===void 0?null:t.pageGutter:e.pageGutter,this.paragraphIndent=e.paragraphIndent===void 0?t.paragraphIndent===void 0?null:t.paragraphIndent:e.paragraphIndent,this.paragraphSpacing=e.paragraphSpacing===void 0?t.paragraphSpacing===void 0?null:t.paragraphSpacing:e.paragraphSpacing,this.scroll=typeof e.scroll==`boolean`?e.scroll:t.scroll??null,this.scrollPaddingTop=e.scrollPaddingTop===void 0?t.scrollPaddingTop===void 0?null:t.scrollPaddingTop:e.scrollPaddingTop,this.scrollPaddingBottom=e.scrollPaddingBottom===void 0?t.scrollPaddingBottom===void 0?null:t.scrollPaddingBottom:e.scrollPaddingBottom,this.scrollPaddingLeft=e.scrollPaddingLeft===void 0?t.scrollPaddingLeft===void 0?null:t.scrollPaddingLeft:e.scrollPaddingLeft,this.scrollPaddingRight=e.scrollPaddingRight===void 0?t.scrollPaddingRight===void 0?null:t.scrollPaddingRight:e.scrollPaddingRight,this.selectionBackgroundColor=e.selectionBackgroundColor||t.selectionBackgroundColor||null,this.selectionTextColor=e.selectionTextColor||t.selectionTextColor||null,this.textAlign=e.textAlign||t.textAlign||null,this.textColor=e.textColor||t.textColor||null,this.textNormalization=typeof e.textNormalization==`boolean`?e.textNormalization:t.textNormalization??null,this.visitedColor=e.visitedColor||t.visitedColor||null,this.wordSpacing=e.wordSpacing===void 0?t.wordSpacing===void 0?null:t.wordSpacing:e.wordSpacing,this.experiments=t.experiments||null}},Gd={oldStyleTf:`'Iowan Old Style', Sitka, 'Sitka Text', Palatino, 'Book Antiqua', 'URW Palladio L', P052, serif`},Kd=16,qd=Gd.oldStyleTf,Jd=class e{constructor(t){this._optimalLineLength=null,this._canvas=document.createElement(`canvas`),this._optimalChars=t.optimalChars,this._minChars=t.minChars,this._maxChars=t.maxChars,this._baseFontSize=t.baseFontSize||Kd,this._fontFace=t.fontFace||qd,this._sample=t.sample||null,this._padding=t.padding??0,this._letterSpacing=t.letterSpacing?Math.round(t.letterSpacing*this._baseFontSize):0,this._wordSpacing=t.wordSpacing?Math.round(t.wordSpacing*this._baseFontSize):0,this._isCJK=t.isCJK||!1,this._getRelative=t.getRelative||!1,this._minDivider=this._minChars&&this._minChars<this._optimalChars?this._optimalChars/this._minChars:this._minChars===null?null:1,this._maxMultiplier=this._maxChars&&this._maxChars>this._optimalChars?this._maxChars/this._optimalChars:this._maxChars===null?null:1,this._approximatedWordSpaces=e.approximateWordSpaces(this._optimalChars,this._sample)}updateMultipliers(){this._minDivider=this._minChars&&this._minChars<this._optimalChars?this._optimalChars/this._minChars:this._minChars===null?null:1,this._maxMultiplier=this._maxChars&&this._maxChars>this._optimalChars?this._maxChars/this._optimalChars:this._maxChars===null?null:1}update(t){t.optimalChars&&(this._optimalChars=t.optimalChars),t.minChars!==void 0&&(this._minChars=t.minChars),t.maxChars!==void 0&&(this._maxChars=t.maxChars),t.baseFontSize&&(this._baseFontSize=t.baseFontSize),t.fontFace!==void 0&&(this._fontFace=t.fontFace||qd),t.letterSpacing&&(this._letterSpacing=t.letterSpacing),t.wordSpacing&&(this._wordSpacing=t.wordSpacing),t.isCJK!=null&&(this._isCJK=t.isCJK),t.padding!==void 0&&(this._padding=t.padding??0),t.getRelative&&(this._getRelative=t.getRelative),t.sample&&(this._sample=t.sample,this._approximatedWordSpaces=e.approximateWordSpaces(this._optimalChars,this._sample)),this.updateMultipliers(),this._optimalLineLength=this.getOptimalLineLength()}get baseFontSize(){return this._baseFontSize}get minimalLineLength(){return this._optimalLineLength||=this.getOptimalLineLength(),this._minDivider===null?null:Math.round(this._optimalLineLength/this._minDivider+this._padding)/(this._getRelative?this._baseFontSize:1)}get maximalLineLength(){return this._optimalLineLength||=this.getOptimalLineLength(),this._maxMultiplier===null?null:Math.round(this._optimalLineLength*this._maxMultiplier+this._padding)/(this._getRelative?this._baseFontSize:1)}get optimalLineLength(){return this._optimalLineLength||=this.getOptimalLineLength(),Math.round(this._optimalLineLength+this._padding)/(this._getRelative?this._baseFontSize:1)}get all(){return this._optimalLineLength||=this.getOptimalLineLength(),{min:this.minimalLineLength,max:this.maximalLineLength,optimal:this.optimalLineLength,baseFontSize:this._baseFontSize}}static approximateWordSpaces(e,t){let n=0;if(t&&t.length>=e){let r=t.match(/([\s]+)/gi);n=(r?r.length:0)*(e/t.length)}return n}getLineLengthFallback(){let e=this._letterSpacing*(this._optimalChars-1),t=this._wordSpacing*this._approximatedWordSpaces;return this._optimalChars*(this._baseFontSize*.5)+e+t}getOptimalLineLength(){if(this._fontFace){if(typeof this._fontFace==`string`)return this.measureText(this._fontFace);{let e=new FontFace(this._fontFace.name,`url(${this._fontFace.url})`);e.load().then(()=>(document.fonts.add(e),this.measureText(e.family)),e=>{})}}return this.getLineLengthFallback()}measureText(t){let n=this._canvas.getContext(`2d`);if(n&&t){let r=this._isCJK?`水`.repeat(this._optimalChars):`0`.repeat(this._optimalChars);if(n.font=`${this._baseFontSize}px ${t}`,this._sample&&this._sample.length>=this._optimalChars&&(r=this._sample.slice(0,this._optimalChars)),Object.hasOwn(n,`letterSpacing`)&&Object.hasOwn(n,`wordSpacing`))return n.letterSpacing=this._letterSpacing.toString()+`px`,n.wordSpacing=this._wordSpacing.toString()+`px`,n.measureText(r).width;{let t=this._letterSpacing*(this._optimalChars-1),i=this._wordSpacing*e.approximateWordSpaces(this._optimalChars,this._sample);return n.measureText(r).width+t+i}}return this.getLineLengthFallback()}},Yd=e=>({frameLoaded:e.frameLoaded||(()=>{}),positionChanged:e.positionChanged||(()=>{}),timelineItemChanged:e.timelineItemChanged||(()=>{}),tap:e.tap||(()=>!1),click:e.click||(()=>!1),zoom:e.zoom||(()=>{}),miscPointer:e.miscPointer||(()=>{}),scroll:e.scroll||(()=>{}),customEvent:e.customEvent||(()=>{}),handleLocator:e.handleLocator||(()=>!1),textSelected:e.textSelected||(()=>{}),contentProtection:e.contentProtection||(()=>{}),contextMenu:e.contextMenu||(()=>{}),peripheral:e.peripheral||(()=>{})});function Xd(e,t){return e.length===t.length&&e.every((e,n)=>e===t[n])}var Zd=class e extends Mc{constructor(t,n,r,i=[],a=void 0,o={preferences:{},defaults:{}}){super(),this._destroyed=!1,this._visibleFragmentIds=[],this._notifiedVisibleFragmentIds=[],this._timelineAugmented=!1,this._preferencesEditor=null,this._injector=null,this._isNavigating=!1,this._navigatorProtector=null,this._keyboardPeripheralsManager=null,this._suspiciousActivityListener=null,this._keyboardPeripheralListener=null,this._decorations=new Map,this._decorationObservers=new Map,this._decorationHoveredDecorations=new Map,this._decorationActivationState=new Map,this._decorationHoverState=new Map,this._decorationActivationConsumed=!1,this.reflowViewport={readingOrder:[],progressions:new Map,positions:null},this.pub=n,this.container=t,this.listeners=Yd(r),this.currentLocation=a,i.length&&(this.positions=i),this._preferences=new Gu(o.preferences),this._defaults=new Ku(o.defaults),this._settings=new Wd(this._preferences,this._defaults);let s=Qc(n.metadata),c=s===`cjk-horizontal`,l=s===`cjk-vertical`,u=l||s===`mongolian-vertical`,d=c||l;this._css=new $u({rsProperties:new Qu({noVerticalPagination:u||void 0}),userProperties:new Zu({}),lineLengths:new Jd({optimalChars:this._settings.optimalLineLength,minChars:this._settings.minimalLineLength,maxChars:this._settings.maximalLineLength,padding:this._settings.scroll?(this._settings.scrollPaddingLeft||0)+(this._settings.scrollPaddingRight||0):(this._settings.pageGutter||0)*2,fontFace:this._settings.fontFamily,letterSpacing:this._settings.letterSpacing,wordSpacing:this._settings.wordSpacing,isCJK:d}),container:t,constraint:this._settings.constraint,isCJKVertical:u}),this._layout=e.determineLayout(n,!!this._settings.scroll),this.currentProgression=n.metadata.effectiveReadingProgression,this._injectablesConfig=o.injectables||{rules:[],allowedDomains:[]},this._readiumRulesPromise=Ud(n.metadata,n.readingOrder.items),this._contentProtection=o.contentProtection||{},this._decoratorConfig=o.decoratorConfig||{},this._decorationResizeSelectors=new Set(this._decoratorConfig.resizeWatchSelectors??[]),this._upgradeInsecureRequests=o.upgradeInsecureRequests??`always`,this._keyboardPeripherals=this.mergeKeyboardPeripherals(this._contentProtection,o.keyboardPeripherals||[]),(this._contentProtection.disableContextMenu||this._contentProtection.checkAutomation||this._contentProtection.checkIFrameEmbedding||this._contentProtection.monitorDevTools||this._contentProtection.protectPrinting?.disable)&&(this._navigatorProtector=new uu(this._contentProtection),this._suspiciousActivityListener=e=>{let{type:t,...n}=e.detail;t===`context_menu`?this.listeners.contextMenu(n):this.listeners.contentProtection(t,n)},window.addEventListener(`readium:navigator:suspiciousActivity`,this._suspiciousActivityListener)),this._keyboardPeripherals.length>0&&(this._keyboardPeripheralsManager=new fu({keyboardPeripherals:this._keyboardPeripherals}),this._keyboardPeripheralListener=e=>{let t=e.detail;this.listeners.peripheral(t)},window.addEventListener(`readium:navigator:keyboardPeripheral`,this._keyboardPeripheralListener)),this.resizeObserver=new ResizeObserver(()=>this.ownerWindow.requestAnimationFrame(async()=>await this.resizeHandler())),this.resizeObserver.observe(this.container.parentElement||document.documentElement)}static determineLayout(e,t){let n=e.metadata.effectiveLayout;if(n===D.fixed||e.metadata.otherMetadata&&`http://openmangaformat.org/schema/1.0#version`in e.metadata.otherMetadata||e.metadata?.conformsTo?.includes(on.DIVINA))return D.fixed;if(n===D.scrolled)return D.scrolled;let r=Qc(e.metadata);return r===`cjk-vertical`||r===`mongolian-vertical`||n===D.reflowable&&t?D.scrolled:D.reflowable}async load(){if(this.positions?.length||(this.positions=await this.pub.positionsFromManifest()),!this._injector){let e=await this._readiumRulesPromise;this._injector=new zl({rules:[...e,...this._injectablesConfig.rules],allowedDomains:this._injectablesConfig.allowedDomains})}if(!this._destroyed){if(this._layout===D.fixed)this.framePool=new Wu(this.container,this.positions,this.pub,this._layout,this._injector,this._contentProtection,this._keyboardPeripherals,[...this._decorationResizeSelectors],this._upgradeInsecureRequests),this.framePool.listener=(e,t)=>{this.eventListener(e,t)};else{if(await this.updateCSS(!1),this._destroyed)return;let e=this.compileCSSProperties(this._css);this.framePool=new wu(this.container,this.positions,e,this._injector,this._contentProtection,this._keyboardPeripherals,e=>this.pub.timeline.segmentsForHref(e).flatMap(e=>e.references).map(e=>{let t=e.indexOf(`#`);return t>=0?e.slice(t+1):``}).filter(Boolean),[...this._decorationResizeSelectors],this._upgradeInsecureRequests)}if(this.currentLocation=this.currentLocation===void 0?this.positions[0]:this.completeLocator(this.currentLocation),await this.resizeHandler(),!this._destroyed)return new Promise(e=>{if(this._destroyed)return e(!1);this.go(this.currentLocation,!1,e)})}}get settings(){if(this._layout===D.fixed)return Object.freeze({...this._settings});{let e=this._css.userProperties.colCount||this._css.rsProperties.colCount||this._settings.columnCount;return Object.freeze({...this._settings,columnCount:e})}}get preferencesEditor(){return this._preferencesEditor===null&&(this._preferencesEditor=new Ju(this._preferences,this.settings,this.pub.metadata)),this._preferencesEditor}async submitPreferences(e){this._preferences=this._preferences.merging(e),await this.applyPreferences()}async applyPreferences(){let e=this._settings;this._settings=new Wd(this._preferences,this._defaults),this._preferencesEditor!==null&&(this._preferencesEditor=new Ju(this._preferences,this.settings,this.pub.metadata)),this._layout===D.fixed?this.handleFXLPrefs(e,this._settings):await this.updateCSS(!0)}handleFXLPrefs(e,t){e.columnCount!==t.columnCount&&this.framePool.setPerPage(t.columnCount)}async updateCSS(e){this._css.update(this._settings),e&&await this.commitCSS(this._css)}compileCSSProperties(e){let t={};for(let[n,r]of Object.entries(e.rsProperties.toCSSProperties()))t[n]=r;for(let[n,r]of Object.entries(e.userProperties.toCSSProperties()))t[n]=r;return t}async commitCSS(e){if(!this.framePool)return;let t=this.compileCSSProperties(e);this.framePool.setCSSProperties(t),this._css.userProperties.view===`paged`&&this._layout===D.scrolled?await this.setLayout(D.reflowable):this._css.userProperties.view===`scroll`&&this._layout===D.reflowable&&await this.setLayout(D.scrolled),this._css.setContainerWidth()}async resizeHandler(){let e=this.container.parentElement||document.documentElement;if(this._layout===D.fixed){let t=Yu(e)-this._settings.constraint;if(Q()?this.container.attributeStyleMap.set(`width`,CSS.px(t)):this.container.style.width=`${t}px`,!this.framePool)return;this.framePool.resizeHandler()}else{let e=this._css.userProperties.colCount,t=this._css.userProperties.lineLength;this._css.resizeHandler(),(this._css.userProperties.view!==`scroll`&&e!==this._css.userProperties.colCount||t!==this._css.userProperties.lineLength)&&await this.commitCSS(this._css)}}get layout(){return this._layout}get ownerWindow(){return this.container.ownerDocument.defaultView||window}get _cframes(){return(this.framePool?.currentFrames??[]).filter(e=>!(e instanceof xu&&e.isDestroyed))}get pool(){return this.framePool}eventListener(e,t,n){switch(e){case`_pong`:if(this.listeners.frameLoaded(this._cframes[0].iframe.contentWindow),this.listeners.positionChanged(this.currentLocation),this._notifyTimelineChange(this.currentLocation),n){let e=this._cframes.filter(e=>!!e).indexOf(n),t=e>=0?this.viewport.readingOrder[e]:void 0;t&&this._reapplyDecorationsToFrame(n,t)}else this._reapplyDecorationsToCurrentFrames();break;case`first_visible_locator`:let r=j.deserialize(t);if(!r)break;this.currentLocation=new j({href:this.currentLocation.href,type:this.currentLocation.type,title:this.currentLocation.title,locations:r?.locations,text:r?.text}),this.listeners.positionChanged(this.currentLocation),this._notifyTimelineChange(this.currentLocation);break;case`text_selected`:{let e=t;if(n){let t=this._cframes.filter(e=>!!e).indexOf(n),r=t>=0?this.viewport.readingOrder[t]:void 0;r&&(e.locator=new j({href:r,type:this.pub.readingOrder.findWithHref(r).type||`application/xhtml+xml`,text:new A({highlight:e.text})}))}this.listeners.textSelected(e);break}case`decoration_activated`:this._handleDecorationActivated(t)&&(this._decorationActivationConsumed=!0);break;case`decoration_pointer_enter`:this._handleDecorationPointerEnter(t);break;case`decoration_pointer_leave`:this._handleDecorationPointerLeave(t);break;case`click`:case`tap`:if(this._decorationActivationConsumed){this._decorationActivationConsumed=!1;break}let i=t;if(i.interactiveElement){let e=new DOMParser().parseFromString(i.interactiveElement,`text/html`).body.children[0];if(e.nodeType===e.ELEMENT_NODE&&e.nodeName===`A`&&e.hasAttribute(`href`)){let t=e.attributes.getNamedItem(`href`)?.value;if(t.startsWith(`#`))this.go(this.currentLocation.copyWithLocations({fragments:[t.substring(1)]}),!1,()=>{});else if(t.startsWith(`http://`)||t.startsWith(`https://`)||t.startsWith(`mailto:`)||t.startsWith(`tel:`))this.listeners.handleLocator(new M({href:t}).locator);else try{this.goLink(new M({href:Zc.join(Zc.dirname(this.currentLocation.href),t)}),!1,()=>{})}catch(e){console.warn(`Couldn't go to link for ${t}: ${e}`),this.listeners.handleLocator(new M({href:t}).locator)}}else console.log(`Clicked on`,e)}else{if(this._layout===D.fixed&&this.framePool.doNotDisturb&&(i.doNotDisturb=!0),this._layout===D.fixed&&(this.currentProgression===R.rtl||this.currentProgression===R.ltr)&&this.framePool.currentFrames.length>1){let e=this.framePool.currentFrames;i.targetFrameSrc===e[this.currentProgression===R.rtl?0:1]?.source&&(i.x+=(e[+(this.currentProgression===R.rtl)]?.iframe.contentWindow?.innerWidth??0)*window.devicePixelRatio)}if(e===`click`?this.listeners.click(i):this.listeners.tap(i))break;let t=(this._cframes.length===2?this._cframes[0].window.innerWidth+this._cframes[1].window.innerWidth:this._cframes[0].window.innerWidth)*window.devicePixelRatio/4;i.x>=t&&i.x<=t*3&&this.listeners.miscPointer(1),i.x<t?this.goLeft(!1,()=>{}):i.x>t*3&&this.goRight(!1,()=>{})}break;case`tap_more`:this.listeners.miscPointer(t);break;case`no_more`:this.changeResource(1);break;case`no_less`:this.changeResource(-1);break;case`swipe`:break;case`scroll`:this.listeners.scroll(t);break;case`zoom`:this.listeners.zoom(t);break;case`progress`:this.syncLocation(t);break;case`content_protection`:let a=t;this.listeners.contentProtection(a.type,a);break;case`context_menu`:this.listeners.contextMenu(t);break;case`keyboard_peripherals`:let o=t,s={...o,interactiveElement:void 0};o.interactiveElement&&(s.interactiveElement=new DOMParser().parseFromString(o.interactiveElement,`text/html`).body.children[0]),this.listeners.peripheral(s);break;case`log`:console.log(this._cframes[0]?.source?.split(`/`)[3],...t);break;default:this.listeners.customEvent(e,t)}}determineModules(){let e=Array.from(Tc.keys());if(this._layout===D.fixed)return e.filter(e=>Sc.includes(e));e=e.filter(e=>Cc.includes(e));let t=Qc(this.pub.metadata);if(t===`cjk-vertical`||t===`mongolian-vertical`)return e.filter(e=>e!==`column_snapper`&&e!==`scroll_snapper`);let n=e;return e=this._layout===D.scrolled?n.filter(e=>e!==`column_snapper`&&e!==`cjk_vertical_snapper`):n.filter(e=>e!==`scroll_snapper`&&e!==`cjk_vertical_snapper`),e}attachListener(){let e=this._cframes.filter(e=>!!e);if(e.length===0)throw Error(`no cframe to attach listener to`);e.forEach(e=>{e.msg&&(e.msg.listener=(t,n)=>{this.eventListener(t,n,e)})}),this._reapplyDecorationsToCurrentFrames()}async apply(){if(await this.framePool.update(this.pub,this.currentLocator,this.determineModules()),this.attachListener(),this.pub.readingOrder.findIndexWithHref(this.currentLocation.href)<0)throw Error(`Link for `+this.currentLocation.href+` not found!`)}supportsDecorationStyle(e){return Fc(e,this._decoratorConfig.decorationTemplates)}registerDecorationObserver(e,t){this._decorationObservers.has(e)||this._decorationObservers.set(e,new Set),this._decorationObservers.get(e).add(t),t.onDecorationActivated&&(this._decorationActivationState.set(e,!0),this._sendDecorationActivationToFrames(e,!0)),(t.onDecorationPointerEnter||t.onDecorationPointerLeave)&&(this._decorationHoverState.set(e,!0),this._sendDecorationHoverToFrames(e,!0))}unregisterDecorationObserver(e){this._decorationObservers.forEach((t,n)=>{if(!t.has(e))return;t.delete(e);let r=[...t].some(e=>e.onDecorationActivated);this._decorationActivationState.has(n)&&!r&&(this._decorationActivationState.delete(n),this._sendDecorationActivationToFrames(n,!1));let i=[...t].some(e=>e.onDecorationPointerEnter||e.onDecorationPointerLeave);this._decorationHoverState.has(n)&&!i&&(this._decorationHoverState.delete(n),this._sendDecorationHoverToFrames(n,!1))})}_sendDecorationActivationToFrames(e,t){this._cframes.filter(e=>!!e).forEach(n=>{n.msg&&n.msg.send(`decoration_activatable`,{group:e,activatable:t})})}_sendDecorationHoverToFrames(e,t){this._cframes.filter(e=>!!e).forEach(n=>{n.msg&&n.msg.send(`decoration_hoverable`,{group:e,hoverable:t})})}addDecorationResizeTarget(e){this._decorationResizeSelectors.add(e),this.framePool?.addResizeTarget(e)}removeDecorationResizeTarget(e){this._decorationResizeSelectors.delete(e),this.framePool?.removeResizeTarget(e)}applyDecorations(e,t){let n=this._decorations.get(t)??[],r=new Map(n.map(e=>[e.id,e])),i=new Map(e.map(e=>[e.id,e])),a=[],o=[],s=[];for(let[e,t]of r)i.has(e)?zc(t,i.get(e))||s.push(i.get(e)):a.push(e);for(let[e,t]of i)r.has(e)||o.push(t);this._decorations.set(t,e),this._sendDecorationOps(t,a,o,s,n);let c=this._decorationActivationState.get(t);c!==void 0&&this._sendDecorationActivationToFrames(t,c);let l=this._decorationHoverState.get(t);l!==void 0&&this._sendDecorationHoverToFrames(t,l)}_sendDecorationOps(e,t,n,r,i){let a=this._cframes.filter(e=>!!e),o=new Map(i.map(e=>[e.id,e])),s=this.viewport.readingOrder;a.forEach((i,a)=>{if(!i.msg)return;let c=s[a];if(c){for(let n of t){let t=o.get(n);!t||t.locator.href!==c||i.msg.send(`decorate`,{group:e,action:`remove`,decoration:{id:n}})}for(let t of n)t.locator.href===c&&i.msg.send(`decorate`,{group:e,action:`add`,decoration:Ic(t,this._decoratorConfig.decorationTemplates)});for(let t of r)t.locator.href===c&&i.msg.send(`decorate`,{group:e,action:`update`,decoration:Ic(t,this._decoratorConfig.decorationTemplates)})}})}_reapplyDecorationsToFrame(e,t){if(e.msg){for(let[n,r]of this._decorations){let i=r.filter(e=>e.locator.href===t);if(i.length!==0){e.msg.send(`decorate`,{group:n,action:`clear`});for(let t of i)e.msg.send(`decorate`,{group:n,action:`add`,decoration:Ic(t,this._decoratorConfig.decorationTemplates)})}}for(let[t,n]of this._decorationActivationState)e.msg.send(`decoration_activatable`,{group:t,activatable:n});for(let[t,n]of this._decorationHoverState)e.msg.send(`decoration_hoverable`,{group:t,hoverable:n})}}_reapplyDecorationsToCurrentFrames(){let e=this._cframes.filter(e=>!!e),t=this.viewport.readingOrder;e.forEach((e,n)=>{let r=t[n];r&&this._reapplyDecorationsToFrame(e,r)})}_handleDecorationActivated(e){let t=this._decorationObservers.get(e.group);if(!t||t.size===0)return!1;let n=(this._decorations.get(e.group)??[]).find(t=>t.id===e.decorationId);if(!n)return!1;let r={decoration:n,group:e.group,rect:e.rect,point:e.point},i=!1;for(let e of t)e.onDecorationActivated?.(r)&&(i=!0);return i}_handleDecorationPointerEnter(e){let t=this._decorationObservers.get(e.group);if(!t||t.size===0)return;let n=(this._decorations.get(e.group)??[]).find(t=>t.id===e.decorationId);if(!n)return;this._decorationHoveredDecorations.set(e.group,n);let r={decoration:n,group:e.group,rect:e.rect,point:e.point};for(let e of t)e.onDecorationPointerEnter?.(r)}_handleDecorationPointerLeave(e){let t=this._decorationObservers.get(e.group);if(!t||t.size===0)return;let n=(this._decorations.get(e.group)??[]).find(t=>t.id===e.decorationId)??this._decorationHoveredDecorations.get(e.group);if(this._decorationHoveredDecorations.delete(e.group),!n)return;let r={decoration:n,group:e.group,rect:e.rect,point:e.point};for(let e of t)e.onDecorationPointerLeave?.(r)}async destroy(){this._destroyed=!0,this._suspiciousActivityListener&&window.removeEventListener(`readium:navigator:suspiciousActivity`,this._suspiciousActivityListener),this._keyboardPeripheralListener&&window.removeEventListener(`readium:navigator:keyboardPeripheral`,this._keyboardPeripheralListener),this._navigatorProtector?.destroy(),this._keyboardPeripheralsManager?.destroy(),await this.framePool?.destroy(),this._decorations.clear(),this._decorationObservers.clear(),this._decorationHoveredDecorations.clear(),this._decorationActivationState.clear(),this._decorationHoverState.clear(),this._decorationResizeSelectors.clear()}async changeResource(e){if(e===0)return!1;if(this._layout===D.fixed){let t=this.framePool,n=t.viewport.positions[0];if(e===1){if(!t.next(t.perPage))return!1}else if(e===-1){if(!t.prev(t.perPage))return!1}else throw Error(`Invalid relative value for FXL`);let r=t.viewport.positions[0];if(n>r){for(let e=this.positions.length-1;e>=0;e--)if(this.positions[e].href===this.pub.readingOrder.items[r-1].href){this.currentLocation=this.positions[e].copyWithLocations({progression:.999999999999});break}}else if(n<r){for(let e=0;e<this.positions.length;e++)if(this.positions[e].href===this.pub.readingOrder.items[r-1].href){this.currentLocation=this.positions[e];break}}return await this.apply(),this.listeners.positionChanged(this.currentLocation),this._notifyTimelineChange(this.currentLocation),!0}let t=this.pub.readingOrder.findIndexWithHref(this.currentLocation.href),n=Math.max(0,Math.min(this.pub.readingOrder.items.length-1,t+e));if(n===t)return this._cframes[0]?.msg?.send(`shake`,void 0,async e=>{}),!1;if(t>n){for(let e=this.positions.length-1;e>=0;e--)if(this.positions[e].href===this.pub.readingOrder.items[n].href){this.currentLocation=this.positions[e].copyWithLocations({progression:.999999999999});break}}else for(let e=0;e<this.positions.length;e++)if(this.positions[e].href===this.pub.readingOrder.items[n].href){this.currentLocation=this.positions[e];break}return await this.apply(),!0}findLastPositionInProgressionRange(e,t){let n=e.findLastIndex(e=>{let n=e.locations.progression;return!!(n&&n>t.start&&n<=t.end)});return n===-1?void 0:e[n]}findNearestPositions(e){let t=this.positions.filter(e=>e.href===this.currentLocation.href),n=this.currentLocation,r,i=t.findLastIndex(t=>(t.locations.progression??0)<=e.start);if(i!==-1){n=t[i];let a=t.slice(i+1);r=this.findLastPositionInProgressionRange(a,e)}return{first:n,last:r}}updateViewport(e){this.reflowViewport.readingOrder=[],this.reflowViewport.progressions.clear(),this.reflowViewport.positions=null,this.currentLocation&&(this.reflowViewport.readingOrder.push(this.currentLocation.href),this.reflowViewport.progressions.set(this.currentLocation.href,e),this.currentLocation.locations?.position!==void 0&&(this.reflowViewport.positions=[this.currentLocation.locations.position],this.lastLocationInView?.locations?.position!==void 0&&this.reflowViewport.positions.push(this.lastLocationInView.locations.position)))}async syncLocation(e){let t=e,n=this.findNearestPositions(t);this.currentLocation=n.first.copyWithLocations({progression:t.start}),this.lastLocationInView=n.last,this.updateViewport(t),this.listeners.positionChanged(this.currentLocation);let r=t.fragmentId?this.currentLocation.copyWithLocations({fragments:[`#${t.fragmentId}`]}):this.currentLocation;this._visibleFragmentIds=t.visibleFragmentIds??[],this._notifyTimelineChange(r),await this.framePool.update(this.pub,this.currentLocation,this.determineModules())}goBackward(e,t){this._isNavigating?t(!1):(this._isNavigating=!0,this._layout===D.fixed?this.changeResource(-1).then(e=>{this._isNavigating=!1,t(e)}):this._cframes[0]?.msg?.send(`go_prev`,void 0,async e=>{if(e)this._isNavigating=!1,t(!0);else{let e=await this.changeResource(-1);this._isNavigating=!1,t(e)}}))}goForward(e,t){this._isNavigating?t(!1):(this._isNavigating=!0,this._layout===D.fixed?this.changeResource(1).then(e=>{this._isNavigating=!1,t(e)}):this._cframes[0]?.msg?.send(`go_next`,void 0,async e=>{if(e)this._isNavigating=!1,t(!0);else{let e=await this.changeResource(1);this._isNavigating=!1,t(e)}}))}get currentLocator(){return this.currentLocation}get viewport(){return this._layout===D.fixed?this.framePool?this.framePool.viewport:{readingOrder:[],progressions:new Map,positions:null}:this.reflowViewport}get isScrollStart(){let e=this.viewport.readingOrder[0];return this.viewport.progressions.get(e)?.start===0}get isScrollEnd(){let e=this.viewport.readingOrder[this.viewport.readingOrder.length-1];return this.viewport.progressions.get(e)?.end===1}get canGoBackward(){let e=this.pub.readingOrder.items[0]?.href;return!(this.viewport.progressions.has(e)&&this.viewport.progressions.get(e)?.start===0)}get canGoForward(){let e=this.pub.readingOrder.items[this.pub.readingOrder.items.length-1]?.href;return!(this.viewport.progressions.has(e)&&this.viewport.progressions.get(e)?.end===1)}get readingProgression(){return this.currentProgression}async setLayout(e){this._layout!==e&&(this._layout=e,await this.framePool.update(this.pub,this.currentLocator,this.determineModules(),!0),this.attachListener())}get publication(){return this.pub}get timeline(){let e=this.pub.timeline;if(!this._timelineAugmented&&this.positions?.length){let t=this.positions,n=new Set;e.augment((e,r)=>{if(e.children?.length)return{};let i=r.href.indexOf(`#`),a=i>=0?r.href.slice(0,i):r.href,o=i>=0?r.href.slice(i+1):void 0,s=t.filter(e=>e.href===a);if(!s.length)return{};let c=o?s.find(e=>e.locations.fragments?.[0]===o):void 0,l;return c?l=c:n.has(a)?l=void 0:(n.add(a),l=s.reduce((e,t)=>(t.locations.position??1/0)<(e.locations.position??1/0)?t:e)),l?{position:l.locations.position,scroll:c?.locations.progression}:{}}),this._timelineAugmented=!0}return this._wrappedTimeline||=new Proxy(e,{get:(e,t)=>{if(t!==`navigableFrom`){let n=Reflect.get(e,t,e);return typeof n==`function`?n.bind(e):n}return t=>{let n=this._visibleFragmentIds,r=(n.length?e.locate(this.currentLocation.copyWithLocations({fragments:[`#${n[0]}`]})):void 0)??t,i=(n.length?e.locate(this.currentLocation.copyWithLocations({fragments:[`#${n[n.length-1]}`]})):void 0)??t;if(this.isScrollStart){let t=e.ancestors(r).find(e=>e.references.includes(this.currentLocation.href));t&&(r=t)}return{previous:e.navigableFrom(r).previous,next:e.navigableFrom(i).next}}}}),this._wrappedTimeline}async loadLocator(e,t){let n=!1,r=Nt(e.locations);if(e.text?.highlight?n=await new Promise((t,n)=>{this._cframes[0].msg.send(`go_text`,r?[e.text?.serialize(),r]:e.text?.serialize(),e=>t(e))}):r&&(n=await new Promise((e,t)=>{this._cframes[0].msg.send(`go_text`,[``,r],t=>e(t))})),n){t(n);return}let i=Rt(e.locations);if(i&&(n=await new Promise((e,t)=>{this._cframes[0].msg.send(`go_id`,i,t=>e(t))})),n){t(n);return}let a=e.locations?.progression;n=a&&a>0?await new Promise((e,t)=>{this._cframes[0].msg.send(`go_progression`,a,t=>e(t))}):!0,t(n)}completeLocator(e){if(!e.href){let t=!1;if(typeof e.locations.position==`number`){let n=this.positions.find(t=>t.locations.position===e.locations.position);n&&(e=n.copyWithLocations(e.locations),t=!0)}if(!t&&typeof e.locations?.totalProgression==`number`){let t=e.locations.totalProgression,n=0,r=1/0;for(let e=0;e<this.positions.length;e++){let i=this.positions[e].locations.totalProgression??e/this.positions.length,a=Math.abs(i-t);a<r&&(r=a,n=e)}e=this.positions[n].copyWithLocations(e.locations)}}return e}go(e,t,n){e=this.completeLocator(e);let r=e.href.split(`#`)[0],i=this.pub.readingOrder.findWithHref(r);if(!i)return n(this.listeners.handleLocator(e));this._isNavigating?n(!1):(this._isNavigating=!0,this.currentLocation=this.positions.find(e=>e.href===i.href),this.apply().then(()=>this.loadLocator(e,e=>{this._isNavigating=!1,n(e)})).then(()=>{this.attachListener()}).catch(e=>{console.error(e),this._isNavigating=!1,n(!1)}))}goLink(e,t,n){return this.go(e.locator,t,n)}_notifyTimelineChange(e){let t=this.timeline.locate(e),n=!Xd(this._visibleFragmentIds,this._notifiedVisibleFragmentIds);(t!==this._currentTimelineItem||n)&&(this._currentTimelineItem=t,this._notifiedVisibleFragmentIds=this._visibleFragmentIds,this.listeners.timelineItemChanged(t))}},Qd=class{constructor(e,t){this.page=O.center,this.addBlank=!1,this.link=e,this.index=t;let n=e.properties?.otherProperties.orientation;this.isLandscape=n===Pu.landscape||n!==Pu.portrait&&(e.width||0)>(e.height||0)}get number(){return this.index+1}get authoredPage(){return this.link.properties?.page}get double(){return this.page===O.center||this.isLandscape||this.addBlank}},$d=class{constructor(e){this.shift=!0,this.pages=[],this.spreads=[],this.itemToSlotArr=[],this.slotToItemArr=[],this.spreadOfItemArr=[],this.rtl=e.metadata.effectiveReadingProgression===R.rtl,this.pages=e.readingOrder.items.map((e,t)=>new Qd(e,t)),this.index(),this.testShift(),this.buildSlots()}index(e=!1){let t=0;this.pages.forEach((n,r)=>{n.page=!n.authoredPage||e?n.isLandscape?O.center:(+!this.shift+r-t)%2?this.rtl?O.right:O.left:this.rtl?O.left:O.right:n.authoredPage,n.double&&t++}),this.buildSpreads()}testShift(){let e=!1;this.spreads.forEach((t,n)=>{if(t.length>1){e=!1;return}let r=t[0];n===0&&(r.isLandscape||r.link.properties?.otherProperties.spread===Fu.both)&&(this.shift=!1),e&&r.page===O.center&&(this.spreads[n-1][0].addBlank=!0),e=!r.isLandscape&&r.page!==O.center&&r.index>0}),this.shift||(this.spreads=[],this.index(!0))}buildSpreads(){this.spreads=[];let e=[];this.pages.forEach((t,n)=>{!n&&this.shift?this.spreads.push([t]):t.page===O.center?(e.length>0&&this.spreads.push(e),this.spreads.push([t]),e=[]):e.length>=2?(this.spreads.push(e),e=[t]):e.push(t)}),e.length>0&&this.spreads.push(e)}buildSlots(){this.itemToSlotArr=Array(this.pages.length),this.slotToItemArr=[],this.spreadOfItemArr=Array(this.pages.length);let e=0;this.spreads.forEach((t,n)=>{t.forEach(r=>{this.itemToSlotArr[r.index]=e,this.spreadOfItemArr[r.index]=n;let i=t.length===1?2:1;for(let t=0;t<i;t++)this.slotToItemArr[e+t]=r.index;e+=i})})}get slotCount(){return this.slotToItemArr.length}get nDouble(){return this.pages.reduce((e,t)=>e+ +!!t.double,0)}slotOfItem(e){return this.itemToSlotArr[Math.max(0,Math.min(e,this.pages.length-1))]??0}itemOfSlot(e){return this.slotToItemArr[Math.max(0,Math.min(e,this.slotToItemArr.length-1))]??0}spreadIndexOfItem(e){return this.spreadOfItemArr[Math.max(0,Math.min(e,this.pages.length-1))]??0}spreadOfItem(e){return this.spreads[this.spreadIndexOfItem(e)]}isDouble(e){return this.spreadOfItem(e)?.length===1}findByHref(e){return this.pages.find(t=>t.link.href===e)}spreadPosition(e,t,n){return n<2||e.length<2?O.center:t===e[0]?this.rtl?O.right:O.left:this.rtl?O.left:O.right}},ef=(e=>(e.auto=`auto`,e.low=`low`,e.high=`high`,e.max=`max`,e))(ef||{}),tf=2560,nf=1800,rf=16;function af(e){let t=e.alternates?.items?[...e.alternates.items]:[];return t.unshift(e),t.filter(e=>!e.type||e.type.startsWith(`image/`))}function of(e,t){let n=e=>(t.axis===`width`?e.width:e.height)||0,r=af(e).filter(e=>n(e)>0);if(r.length<=1)return r[0]||e;let i=r.sort((e,t)=>n(e)-n(t)),a=B.OS.iOS||B.OS.Android?t.axis===`width`?nf:tf:1/0,o=e=>{if(n(e)<=a)return e;let t=i.filter(t=>t===e||n(t)<=a);return t.length>1?t[t.length-2]:i[0]};switch(t.quality){case`low`:return i[0];case`max`:return o(i[i.length-1]);default:{let e=Math.min(t.axis===`width`?t.targetWidth:t.targetHeight,a),r=i.find(t=>n(t)>=e-rf)||i[i.length-1];if(t.quality===`high`){let e=i[i.indexOf(r)+1];e&&(r=e)}return o(r)}}}var sf=e=>e.replace(/&/g,`&amp;`).replace(/</g,`&lt;`).replace(/>/g,`&gt;`),cf=new Map;function lf(e,t,n,r){let i=`${e}x${t}|${n}|${r??``}`,a=cf.get(i);if(a)return a;let o=Math.max(24,Math.round(Math.min(e,t)/10));n=sf(n),r&&=sf(r);let s=`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${e} ${t}"><rect width="100%" height="100%" fill="rgba(128,128,128,0.08)"/><text x="50%" y="50%" text-anchor="middle" dominant-baseline="central" font-family="sans-serif" font-weight="bold" font-size="${o}" fill="#999">${n}</text>`+(r?`<text x="50%" y="97%" text-anchor="middle" font-family="sans-serif" font-size="${Math.round(o/3)}" fill="#aaa">${r.length>40?`…`+r.slice(r.length-40):r}</text>`:``)+`</svg>`,c=`data:image/svg+xml,${encodeURIComponent(s)}`;return cf.set(i,c),c}var uf=1080,df=1440,ff=class{constructor(e,t,n=()=>ef.auto){this.objectURL=null,this.loadPromise=null,this.abortController=null,this._loaded=!1,this.destroyed=!1,this.generation=0,this.mode=`paged`,this.page=e,this.fetchBlob=t,this.getQuality=n,this.wrapper=document.createElement(`div`),this.wrapper.style.position=`relative`,this.wrapper.style.overflow=`hidden`,this.wrapper.dataset.href=e.link.href,this.wrapper.dataset.pageNumber=`${e.number}`,this.img=document.createElement(`img`),this.img.decoding=`async`,this.img.draggable=!1,this.img.alt=e.link.title||`Page ${e.number}`,this.img.style.display=`block`,this.img.style.userSelect=`none`,this.img.style.webkitUserSelect=`none`,this.img.style.webkitUserDrag=`none`,this.placeholder=lf(this.intrinsicWidth,this.intrinsicHeight,`···`,this.page.link.title?this.page.link.title:`Page ${this.page.number}`),this.img.src=this.placeholder,this.wrapper.appendChild(this.img)}get intrinsicWidth(){return this.page.link.width||(this._loaded?this.img.naturalWidth:0)||uf}get intrinsicHeight(){return this.page.link.height||(this._loaded?this.img.naturalHeight:0)||df}get loaded(){return this._loaded}get element(){return this.wrapper}setMode(e){this.mode=e,Q()?e===`paged`?([`margin-top`,`margin-right`,`margin-bottom`,`margin-left`].forEach(e=>this.wrapper.attributeStyleMap.delete(e)),this.img.attributeStyleMap.set(`position`,`absolute`),this.img.attributeStyleMap.set(`top`,CSS.px(0)),this.img.attributeStyleMap.set(`left`,CSS.px(0)),this.img.attributeStyleMap.set(`width`,CSS.percent(100)),this.img.attributeStyleMap.set(`height`,CSS.percent(100)),this.img.attributeStyleMap.set(`object-fit`,`contain`),this.img.attributeStyleMap.delete(`aspect-ratio`)):(this.wrapper.attributeStyleMap.set(`float`,`none`),this.wrapper.attributeStyleMap.set(`width`,CSS.percent(100)),this.wrapper.attributeStyleMap.set(`height`,`auto`),this.wrapper.attributeStyleMap.set(`margin-top`,CSS.px(0)),this.wrapper.attributeStyleMap.set(`margin-bottom`,CSS.px(0)),this.wrapper.attributeStyleMap.set(`margin-left`,`auto`),this.wrapper.attributeStyleMap.set(`margin-right`,`auto`),this.img.attributeStyleMap.set(`position`,`static`),this.img.attributeStyleMap.delete(`top`),this.img.attributeStyleMap.delete(`left`),this.img.attributeStyleMap.set(`width`,CSS.percent(100)),this.img.attributeStyleMap.set(`height`,`auto`),this.img.attributeStyleMap.delete(`object-fit`),this.img.attributeStyleMap.set(`aspect-ratio`,`${this.intrinsicWidth} / ${this.intrinsicHeight}`)):e===`paged`?(this.wrapper.style.removeProperty(`margin`),this.img.style.position=`absolute`,this.img.style.top=`0`,this.img.style.left=`0`,this.img.style.width=`100%`,this.img.style.height=`100%`,this.img.style.objectFit=`contain`,this.img.style.removeProperty(`aspect-ratio`)):(this.wrapper.style.cssFloat=this.wrapper.style.float=`none`,this.wrapper.style.width=`100%`,this.wrapper.style.height=`auto`,this.wrapper.style.margin=`0 auto`,this.img.style.position=`static`,this.img.style.removeProperty(`top`),this.img.style.removeProperty(`left`),this.img.style.width=`100%`,this.img.style.height=`auto`,this.img.style.removeProperty(`object-fit`),this.img.style.aspectRatio=`${this.intrinsicWidth} / ${this.intrinsicHeight}`)}fit(e,t=!1){if(this.mode!==`paged`)return;let n,r,i;t&&e!==O.center?(n=50,r=e===O.right?50:0,i=`center center`):(n=100,r=0,i=e===O.left?`right center`:e===O.right?`left center`:`center center`),Q()?(this.img.attributeStyleMap.set(`width`,CSS.percent(n)),this.img.attributeStyleMap.set(`left`,CSS.percent(r)),this.img.attributeStyleMap.set(`object-position`,i)):(this.img.style.width=`${n}%`,this.img.style.left=`${r}%`,this.img.style.objectPosition=i)}applyStripWidth(e){this.mode===`scrolled`&&(Q()?(this.wrapper.attributeStyleMap.set(`width`,CSS.px(Math.round(e))),this.wrapper.attributeStyleMap.set(`max-width`,CSS.percent(100))):(this.wrapper.style.width=`${Math.round(e)}px`,this.wrapper.style.maxWidth=`100%`))}pickVariant(){let e=window.devicePixelRatio||1,t=this.wrapper.clientWidth||0,n=this.wrapper.clientHeight||0,r=t*e,i=n*e;if(this.mode===`paged`&&t>0&&n>0){let a=Math.min(t/this.intrinsicWidth,n/this.intrinsicHeight);r=this.intrinsicWidth*a*e,i=this.intrinsicHeight*a*e}return of(this.page.link,{targetWidth:r,targetHeight:i,axis:this.mode===`scrolled`?`width`:`height`,quality:this.getQuality()})}async load(){if(this._loaded||this.destroyed)return;if(this.loadPromise)return this.loadPromise;let e=this.generation;this.abortController=new AbortController;let t=this.abortController.signal;return this.loadPromise=(async()=>{try{let n=await this.fetchBlob(this.pickVariant(),t);if(this.destroyed||e!==this.generation)return;let r=URL.createObjectURL(n);try{await new Promise((e,t)=>{let n=()=>{a(),e()},i=()=>{a(),t(Error(`Failed to decode ${this.page.link.href}`))},a=()=>{this.img.removeEventListener(`load`,n),this.img.removeEventListener(`error`,i)};this.img.addEventListener(`load`,n),this.img.addEventListener(`error`,i),this.img.src=r})}catch(e){throw URL.revokeObjectURL(r),e}if(this.destroyed||e!==this.generation){URL.revokeObjectURL(r),this.img.src===r&&(this.img.src=this.placeholder);return}if(this.objectURL=r,this._loaded=!0,this.mode===`scrolled`&&this.img.naturalWidth&&this.img.naturalHeight){let e=`${this.img.naturalWidth} / ${this.img.naturalHeight}`;Q()?this.img.attributeStyleMap.set(`aspect-ratio`,e):this.img.style.aspectRatio=e}}catch(t){!this.destroyed&&e===this.generation&&(console.warn(`Divina page load failed`,this.page.link.href,t),this.img.src=lf(this.intrinsicWidth,this.intrinsicHeight,`!`,this.page.link.title?this.page.link.title:`Page ${this.page.number}`))}finally{e===this.generation&&(this.loadPromise=null)}})(),this.loadPromise}unload(){!this._loaded&&!this.loadPromise||(this.generation++,this._loaded=!1,this.loadPromise=null,this.abortController?.abort(),this.abortController=null,this.img.src=this.placeholder,this.objectURL&&=(URL.revokeObjectURL(this.objectURL),null))}destroy(){this.destroyed=!0,this.unload(),this.wrapper.remove()}},pf=6,mf=1.02,hf=.5,gf=50,_f=5,vf=200,yf=300,bf=60,xf=class{constructor(e){this.dragState=0,this.minimumMoved=!1,this.pan={startX:0,endX:0,startY:0,overscrollX:0,overscrollY:0,letItGo:!1,preventClick:!1,translateX:0,translateY:0,touchID:0},this.pinch={startDistance:0,startScale:0,target:{X:0,Y:0},touchN:0,startTranslate:{X:0,Y:0}},this._scale=1,this.scaleDebouncer=0,this.frameBounds=null,this.destroyed=!1,this.mouseDown=null,this.clickTimer=0,this.lastTouchEnd=0,this.tapTimer=0,this.lastTapTime=0,this.lastTapX=0,this.lastTapY=0,this.wheelHot=!1,this.wheelLastDir=0,this.wheelLastMag=0,this.wheelDecelCount=0,this.wheelLastEvent=0,this.wheelCooldownTimer=0,this.btouchstartHandler=this.touchstartHandler.bind(this),this.btouchendHandler=this.touchendHandler.bind(this),this.btouchmoveHandler=this.touchmoveHandler.bind(this),this.bdblclickHandler=this.dblclickHandler.bind(this),this.bmousedownHandler=this.mousedownHandler.bind(this),this.bmouseupHandler=this.mouseupHandler.bind(this),this.bmousemoveHandler=this.mousemoveHandler.bind(this),this.bwheelHandler=this.wheelHandler.bind(this),this.moveFrame=0,this.dragTranslate=null,this.dragTransform=null,this.manager=e,this.coordinator=new Du,this.observe(this.manager.spineElement),this.manager.bookElement.addEventListener(`wheel`,this.bwheelHandler,{passive:!1})}get scale(){return this._scale}set scale(e){isNaN(e)&&(e=1),window.clearTimeout(this.scaleDebouncer),this.scaleDebouncer=window.setTimeout(()=>{this.dragState===0&&this.scale<mf&&(this.pan.translateX=0,this.pan.translateY=0,this.clearPan(),this.manager.updateBookStyle()),this.manager.listener(`zoom`,e)},100),this._scale=e}observe(e){e.addEventListener(`touchstart`,this.btouchstartHandler),e.addEventListener(`touchend`,this.btouchendHandler),e.addEventListener(`touchmove`,this.btouchmoveHandler,{passive:!0}),e.addEventListener(`dblclick`,this.bdblclickHandler,{passive:!0}),e.addEventListener(`mousedown`,this.bmousedownHandler),e.addEventListener(`mouseup`,this.bmouseupHandler),e.addEventListener(`mousemove`,this.bmousemoveHandler)}unobserve(e){e.removeEventListener(`touchstart`,this.btouchstartHandler),e.removeEventListener(`touchend`,this.btouchendHandler),e.removeEventListener(`touchmove`,this.btouchmoveHandler),e.removeEventListener(`dblclick`,this.bdblclickHandler),e.removeEventListener(`mousedown`,this.bmousedownHandler),e.removeEventListener(`mouseup`,this.bmouseupHandler),e.removeEventListener(`mousemove`,this.bmousemoveHandler)}destroy(){this.destroyed=!0,this.unobserve(this.manager.spineElement),this.manager.bookElement.removeEventListener(`wheel`,this.bwheelHandler),window.clearTimeout(this.scaleDebouncer),window.clearTimeout(this.wheelCooldownTimer),window.clearTimeout(this.clickTimer),window.clearTimeout(this.tapTimer),cancelAnimationFrame(this.moveFrame)}clearPan(){this.pan.letItGo=!1,this.pan.touchID=0,this.pan.endX=0,this.pan.overscrollX=0,this.pan.overscrollY=0}clearPinch(){this.pinch={startDistance:0,startScale:this.pinch.startScale,target:{X:0,Y:0},touchN:0,startTranslate:{X:0,Y:0}}}get isScaled(){return this.scale>1}resetZoom(){this.scale=1,this.pan.translateX=0,this.pan.translateY=0,this.manager.updateBookStyle()}emitPointer(e,t,n){let r=this.manager.bookElement.getBoundingClientRect(),i=window.devicePixelRatio||1,a={x:(t-r.left)*i,y:(n-r.top)*i,clientX:t,clientY:n,doNotDisturb:this.pan.touchID>0||this.dragState>0};this.manager.listener(e,a)}touchstartHandler(e){if([`TEXTAREA`,`OPTION`,`INPUT`,`SELECT`].indexOf(e.target.nodeName)!==-1)return;switch(e.stopPropagation(),this.frameBounds=this.manager.currentBounds,this.coordinator.refreshOuterPixels(this.frameBounds),e.touches.length){case 3:return;case 2:{e.preventDefault(),this.pinch.startDistance=this.coordinator.getTouchDistance(e);let t=this.startTouch(e);this.pan.startX=t.X,this.pan.startY=t.Y,this.dragState=2,this.manager.updateBookStyle(!0),this.isScaled?(this.pinch.target.X-=this.pan.translateX*(this.pinch.startScale/this.scale),this.pinch.target.Y-=this.pan.translateY*(this.pinch.startScale/this.scale),this.pinch.target={X:0,Y:0},this.pinch.startScale=1/this.scale):(this.pinch.target={X:0,Y:0},this.pinch.startScale=this.scale),this.pinch.startTranslate={X:this.pan.translateX,Y:this.pan.translateY};return}case 1:this.pan.touchID=e.touches[0].identifier;default:this.dragState<1&&(this.dragState=1),this.manager.updateBookStyle(!0)}this.manager.updateSpineStyle(!1);let t=this.startTouch(e);this.pan.startX=t.X,this.pan.startY=t.Y}startTouch(e){let t=this.coordinator.getTouchCenter(e)||this.coordinator.getBibiEventCoord(e);return{X:t.X-this.manager.width/2-this.pan.translateX*this.scale+this.manager.width/2,Y:t.Y-this.manager.height/2-this.pan.translateY*this.scale+this.manager.height/2}}touchendHandler(e){if(e.stopPropagation(),!e.touches||e.touches.length===0){let t=this.pinch.touchN>0;if(this.pan.endX&&!this.isScaled)this.pinch.touchN&&(this.pan.endX=this.pan.startX),this.updateAfterDrag();else if(!this.pinch.touchN&&Math.abs(this.pan.overscrollX)>gf&&Math.abs(this.pan.overscrollY)<gf/2)this.pan.startX=0,this.pan.endX=-this.pan.overscrollX,this.updateAfterDrag();else if(!this.minimumMoved&&!t&&e.changedTouches?.length===1){e.cancelable&&e.preventDefault(),this.lastTouchEnd=performance.now(),this.dragState=0,this.clearPan();let{clientX:t,clientY:n}=e.changedTouches[0],r=performance.now();r-this.lastTapTime<yf&&Math.abs(t-this.lastTapX)+Math.abs(n-this.lastTapY)<bf?(window.clearTimeout(this.tapTimer),this.lastTapTime=0,this.toggleZoom(t,n)):(this.lastTapTime=r,this.lastTapX=t,this.lastTapY=n,window.clearTimeout(this.tapTimer),this.tapTimer=window.setTimeout(()=>this.emitPointer(`tap`,t,n),yf))}this.dragState=0,this.minimumMoved=!1,this.clearPinch()}else if(e.touches.length===1){this.dragState=1,e.touches[0].identifier!==this.pan.touchID&&(this.pan.touchID=e.touches[0].identifier);let t=this.startTouch(e);this.pan.startX=t.X,this.pan.startY=t.Y}window.setTimeout(()=>{this.destroyed||(this.manager.updateBookStyle(!0),this.dragState===0&&(this.scale<mf&&(this.pan.translateX=0,this.pan.translateY=0),this.clearPan()),this.manager.updateBookStyle(!0))},50)}touchmoveHandler(e){e.stopPropagation();let t=this.coordinator.getBibiEventCoord(e);Math.abs(this.pan.startY-t.Y)+Math.abs(this.pan.startX-t.X)>_f&&(this.minimumMoved||=(this.manager.deselect(),!0),this.dragState<1&&(this.dragState=1));let n=this.coordinator?.getTouchDistance(e),r=!1,i=this.scale;if(this.dragState===2&&n){if(this.pinch.touchN++,this.pinch.touchN<4)return;let e=n/this.pinch.startDistance*this.scale;e>=pf&&(e=pf),e<=mf&&(e=1),this.scale=e,this.pinch.startDistance=n,r=!0}if(this.pan.letItGo===!1&&(this.pan.letItGo=Math.abs(this.pan.startY-t.Y)<Math.abs(this.pan.startX-t.X)),this.dragState>0&&this.isScaled||this.dragState>1){if(this.dragState===1){let e={X:t.X-this.manager.width/2,Y:t.Y-this.manager.height/2};this.pan.translateX=(e.X-(this.pan.startX-this.manager.width/2))*1/this.scale,this.pan.translateY=(e.Y-(this.pan.startY-this.manager.height/2))*1/this.scale}else if(this.dragState===2){let t=this.coordinator.getTouchCenter(e);t.X-=this.manager.width/2,t.Y-=this.manager.height/2;let n=-t.X/i;n+=t.X/this.scale,this.pinch.target.X+=n,t.X+=this.pinch.target.X*this.scale/this.pinch.startScale;let r=-t.Y/i;r+=t.Y/this.scale,this.pinch.target.Y+=r,t.Y+=this.pinch.target.Y*this.scale/this.pinch.startScale,this.pan.translateX=(t.X-(this.pan.startX-this.manager.width/2))*1/this.scale,this.pan.translateY=(t.Y-(this.pan.startY-this.manager.height/2))*1/this.scale}let n=this.frameBounds.width/6,a=this.frameBounds.height/6;this.pan.translateX<-n&&(this.pan.overscrollX=-(n+this.pan.translateX),this.pan.translateX=-n),this.pan.translateY<-a&&(this.pan.overscrollY=-(a+this.pan.translateY),this.pan.translateY=-a),this.pan.translateX>n&&(this.pan.overscrollX=n-this.pan.translateX,this.pan.translateX=n),this.pan.translateY>a&&(this.pan.overscrollY=a-this.pan.translateY,this.pan.translateY=a),r=!0}if(r)this.manager.updateBookStyle();else if(this.dragState>0&&this.pan.letItGo){this.pan.endX=t.X;let e=this.manager.currentSlide*(this.manager.width/this.manager.perPage),n=this.pan.endX-this.pan.startX,r=this.manager.rtl?e+n:e-n,i=window.devicePixelRatio||1,a=Math.round((this.manager.rtl?1:-1)*r*i)/i;cancelAnimationFrame(this.moveFrame),this.moveFrame=requestAnimationFrame(()=>{requestAnimationFrame(()=>{this.destroyed||(Q()?(this.dragTransform||=(this.dragTranslate=new CSSTranslate(CSS.px(0),CSS.px(0),CSS.px(0)),new CSSTransformValue([this.dragTranslate])),this.dragTranslate.x.value=a,this.manager.spineElement.attributeStyleMap.set(`transform`,this.dragTransform)):this.manager.spineElement.style.transform=`translate3d(${a}px, 0, 0)`)})})}}toggleZoom(e,t){if(this.isScaled){this.resetZoom();return}let n=this.manager.bookElement.getBoundingClientRect(),r=e-n.left,i=t-n.top;this.frameBounds=this.manager.currentBounds;let a=this.frameBounds.width/6,o=this.frameBounds.height/6;this.scale=2,this.pan.translateX=Math.max(-a,Math.min(a,this.manager.width/2-r)),this.pan.translateY=Math.max(-o,Math.min(o,this.manager.height/2-i)),this.manager.updateBookStyle()}zoomBy(e){let t=this.scale+e;t>=pf&&(t=pf),t<=mf&&(t=1),this.scale=t,t===1&&(this.pan.translateX=0,this.pan.translateY=0),this.manager.updateBookStyle()}zoomIn(){this.zoomBy(hf)}zoomOut(){this.zoomBy(-.5)}dblclickHandler(e){window.clearTimeout(this.clickTimer),this.toggleZoom(e.clientX,e.clientY)}addTouch(e){e.touches=[{pageX:e.pageX,pageY:e.pageY}]}mousedownHandler(e){this.mouseDown={X:e.clientX,Y:e.clientY},this.isScaled&&(this.addTouch(e),this.touchstartHandler(e))}mouseupHandler(e){let t=this.mouseDown;if(this.mouseDown=null,this.isScaled&&this.touchendHandler(e),!(performance.now()-this.lastTouchEnd<700||e.detail>1)&&t&&e.button===0&&Math.abs(e.clientX-t.X)+Math.abs(e.clientY-t.Y)<=_f){let{clientX:t,clientY:n}=e;window.clearTimeout(this.clickTimer),this.clickTimer=window.setTimeout(()=>this.emitPointer(`click`,t,n),250)}}mousemoveHandler(e){this.isScaled&&e.buttons>0&&(e.preventDefault(),this.addTouch(e),this.touchmoveHandler(e))}wheelHandler(e){if(e.preventDefault(),e.ctrlKey){let t=this.scale*(1-e.deltaY*.01);t>=pf&&(t=pf),t<=mf&&(t=1),this.scale=t,this.manager.updateBookStyle();return}let t=Math.abs(e.deltaX)>Math.abs(e.deltaY),n=t?e.deltaX:e.deltaY,r=Math.abs(n);if(r<1)return;let i=Math.sign(n);t&&this.manager.rtl&&(i=-i);let a=performance.now(),o=a-this.wheelLastEvent;this.wheelLastEvent=a;let s=null;o>vf?s=`start`:this.wheelLastDir!==0&&i!==this.wheelLastDir?s=`reverse`:this.wheelDecelCount>=3&&r>this.wheelLastMag*1.5&&(s=`serial`),this.wheelDecelCount=r<=this.wheelLastMag?this.wheelDecelCount+1:0,this.wheelLastMag=r,this.wheelLastDir=i,s!==null&&(!this.wheelHot||s===`reverse`||s===`serial`)&&(this.wheelHot=!0,(s===`serial`||s===`reverse`)&&(this.wheelDecelCount=0),this.manager.listener(i>0?`no_more`:`no_less`,void 0)),window.clearTimeout(this.wheelCooldownTimer),this.wheelCooldownTimer=window.setTimeout(()=>{this.wheelHot=!1,this.wheelLastDir=0,this.wheelLastMag=0,this.wheelDecelCount=0},vf)}updateAfterDrag(){let e=(this.manager.rtl?-1:1)*(this.pan.endX-this.pan.startX),t=Math.abs(e);e>0&&t>this.manager.threshold&&this.manager.length>this.manager.perPage?this.manager.listener(`no_less`,void 0):e<0&&t>this.manager.threshold&&this.manager.length>this.manager.perPage&&this.manager.listener(`no_more`,void 0),this.manager.slideToCurrent(!0,!0)}},Sf=8,Cf=4,wf=300,Tf=150,Ef=500,Df=class{constructor(e,t,n,r,i){this.width=0,this.height=0,this.currentSlide=0,this.orientationInternal=-1,this.destroyed=!1,this.loadTimers=new Map,this.listener=()=>{},this.bookScale=null,this.bookTranslate=null,this.bookTransform=null,this.container=e,this.pub=t,this.spreader=n,this.pool=r,this.spread=i,this.containerHeightCached=e.clientHeight,this.bookElement=document.createElement(`div`),this.bookElement.ariaLabel=`Book`,this.bookElement.tabIndex=-1,this.updateBookStyle(!0),this.spineElement=document.createElement(`div`),this.spineElement.ariaLabel=`Spine`,this.bookElement.appendChild(this.spineElement),this.container.appendChild(this.bookElement);let a=document.createDocumentFragment();this.spreader.pages.forEach(e=>{let t=this.pool.get(e.index);t.setMode(`paged`),t.wrapper.style.cssFloat=t.wrapper.style.float=this.rtl?`right`:`left`,t.wrapper.style.contain=`strict`,a.appendChild(t.wrapper)}),this.spineElement.appendChild(a),this.updateSpineStyle(!1),this.updateSlotSizes(),this.peripherals=new xf(this)}get rtl(){return this.pub.metadata.effectiveReadingProgression===R.rtl}get single(){return!this.spread||this.portrait}get perPage(){return this.spread&&!this.portrait?2:1}get threshold(){return 50}get portrait(){return this.orientationInternal===-1&&(this.orientationInternal=+(this.containerHeightCached>this.container.clientWidth)),this.orientationInternal===1}get slength(){return this.spreader.pages.length}get length(){return this.single?this.slength:this.spreader.slotCount}slotEdge(e){let t=window.devicePixelRatio||1;return Math.round(e*(this.width/this.perPage)*t)/t}get offset(){return(this.rtl?1:-1)*this.slotEdge(this.currentSlide)}get doNotDisturb(){return this.peripherals.pan.touchID>0}get currentIndex(){return this.single?Math.max(0,Math.min(this.currentSlide,this.slength-1)):this.spreader.itemOfSlot(this.currentSlide)}get currentSpread(){return this.perPage<2?[this.spreader.pages[this.currentIndex]]:this.spreader.spreadOfItem(this.currentIndex)}updateDimensions(){this.width=this.bookElement.clientWidth,this.height=this.bookElement.clientHeight}updateBookStyle(e=!1){if(e){let e={overflow:`hidden`,direction:this.pub.metadata.effectiveReadingProgression,cursor:``,height:`100%`,width:`100%`,position:`relative`,outline:`none`,transition:this.peripherals?.dragState?`none`:`transform .15s ease-in-out`,touchAction:`none`};Object.assign(this.bookElement.style,e)}let t=this.peripherals?.scale||1,n=this.peripherals?.pan.translateX||0,r=this.peripherals?.pan.translateY||0;Q()?(this.bookTransform||=(this.bookScale=new CSSScale(1,1),this.bookTranslate=new CSSTranslate(CSS.px(0),CSS.px(0),CSS.px(0)),new CSSTransformValue([this.bookScale,this.bookTranslate])),this.bookScale.x.value=t,this.bookScale.y.value=t,this.bookTranslate.x.value=n,this.bookTranslate.y.value=r,this.bookElement.attributeStyleMap.set(`transform`,this.bookTransform)):this.bookElement.style.transform=`scale(${t}) translate3d(${n}px, ${r}px, 0px)`}updateSpineStyle(e,t=!0){if(this.updateDimensions(),Q())this.spineElement.attributeStyleMap.set(`transition`,new CSSUnparsedValue([e?`all ${t?Tf:Ef}ms ease-out`:`all 0ms ease-out`])),this.spineElement.attributeStyleMap.set(`width`,CSS.px(this.slotEdge(this.length))),this.spineElement.attributeStyleMap.set(`height`,CSS.percent(100)),this.transform===void 0?this.spineElement.attributeStyleMap.delete(`transform`):this.spineElement.attributeStyleMap.set(`transform`,new CSSTransformValue([new CSSTranslate(CSS.px(this.transform||0),CSS.px(0),CSS.px(0))])),this.spineElement.attributeStyleMap.set(`contain`,new CSSUnparsedValue([`content`]));else{let n={transition:e?`all ${t?Tf:Ef}ms ease-out`:`all 0ms ease-out`,width:`${this.slotEdge(this.length)}px`,height:`100%`,transform:this.transform===void 0?``:`translate3d(${this.transform}px, 0px, 0px)`,contain:`content`};Object.assign(this.spineElement.style,n)}}updateSlotSizes(){this.updateDimensions();let e=Q();this.spreader.pages.forEach(t=>{let n=this.pool.get(t.index),r=!this.single&&this.spreader.isDouble(t.index)?2:1,i=this.single?t.index:this.spreader.slotOfItem(t.index),a=this.slotEdge(i+r)-this.slotEdge(i);e?(n.wrapper.attributeStyleMap.set(`width`,CSS.px(a)),n.wrapper.attributeStyleMap.set(`height`,CSS.px(this.height))):(n.wrapper.style.width=`${a}px`,n.wrapper.style.height=`${this.height}px`)})}reAlign(e=this.currentSlide){return e%2&&!this.single&&e++,e}slideToCurrent(e,t=!0){this.updateDimensions();let n=e=>{this.transform=this.offset,this.updateSpineStyle(e,t),this.deselect()};e?requestAnimationFrame(()=>{requestAnimationFrame(()=>n(!0))}):n(!1)}bounce(e=!1){requestAnimationFrame(()=>{this.transform=this.offset+50*(e?1:-1),this.updateSpineStyle(!0,!0),setTimeout(()=>{this.destroyed||(this.transform=this.offset,this.updateSpineStyle(!0,!0))},100)})}onChange(){this.peripherals.scale=1,this.peripherals.pan.translateX=0,this.peripherals.pan.translateY=0,this.updateBookStyle()}next(){if(this.length<=this.perPage)return!1;let e=this.currentSlide;return this.currentSlide=Math.min(this.currentSlide+this.perPage,this.length-this.perPage),this.currentSlide=this.reAlign(),e===this.currentSlide?(this.bounce(this.rtl),!1):(this.slideToCurrent(!0),this.onChange(),!0)}prev(){if(this.length<=this.perPage)return!1;let e=this.currentSlide;return this.currentSlide=this.reAlign(Math.max(this.currentSlide-this.perPage,0)),e===this.currentSlide?(this.bounce(!this.rtl),!1):(this.slideToCurrent(!0),this.onChange(),!0)}slideForItem(e){let t=Math.max(0,Math.min(e,this.slength-1));return this.single?t:this.spreader.slotOfItem(this.spreader.spreadOfItem(t)[0].index)}goToItem(e,t=!0){let n=this.slideForItem(e);return n!==this.currentSlide&&(this.currentSlide=n,this.slideToCurrent(t),this.onChange(),!0)}async update(){if(this.destroyed)return;let e=this.currentIndex,t=this.currentSpread,n=new Set(t.map(e=>e.index));this.spreader.pages.forEach(t=>{let r=this.pool.get(t.index),i=Math.abs(t.index-e);if(i>Sf){let e=this.loadTimers.get(t.index);e&&(clearTimeout(e),this.loadTimers.delete(t.index)),r.unload()}else if(i<=Cf&&!n.has(t.index)&&!r.loaded&&!this.loadTimers.has(t.index)){let e=window.setTimeout(()=>{this.loadTimers.delete(t.index),this.destroyed||r.load()},wf);this.loadTimers.set(t.index,e)}}),await Promise.all(t.map(e=>{let n=this.pool.get(e.index),r=this.loadTimers.get(e.index);return r&&(clearTimeout(r),this.loadTimers.delete(e.index)),this.placePage(t,e),n.load()}))}placePage(e,t){let n=this.pool.get(t.index);n&&(this.perPage>1&&e.length===1&&!t.isLandscape&&t.page!==O.center?n.fit(t.page,!0):n.fit(this.spreader.spreadPosition(e,t,this.perPage)))}get currentBounds(){let e={x:0,y:0,width:0,height:0,top:0,right:0,bottom:0,left:0,toJSON(){return this}};return this.currentSpread.forEach(t=>{let n=this.pool.get(t.index);if(!n)return;let r=n.img.getBoundingClientRect();e.x=Math.min(e.x,r.x),e.y=Math.min(e.y,r.y),e.width+=r.width,e.height=Math.max(e.height,r.height),e.top=Math.min(e.top,r.top),e.right=Math.min(e.right,r.right),e.bottom=Math.min(e.bottom,r.bottom),e.left=Math.min(e.left,r.left)}),e}get viewport(){let e={readingOrder:[],progressions:new Map,positions:null},t=[];return this.currentSpread.forEach(n=>{e.readingOrder.push(n.link.href),e.progressions.set(n.link.href,{start:0,end:1}),t.push(n.number)}),e.positions=t,e}resizeHandler(e=!0,t=!0){let n=this.currentIndex;this.containerHeightCached=this.container.clientHeight,this.orientationInternal=-1,this.currentSlide=this.slideForItem(n),this.updateSpineStyle(!1),this.updateSlotSizes(),e&&this.slideToCurrent(!t,t);let r=this.currentSpread;r.forEach(e=>this.placePage(r,e))}setSpreads(e){if(this.spread===e)return;let t=this.currentIndex;this.spread=e,this.currentSlide=this.slideForItem(t),requestAnimationFrame(()=>{this.destroyed||(this.resizeHandler(!0),this.update())})}deselect(){this.container.ownerDocument.defaultView?.getSelection()?.removeAllRanges()}async destroy(){this.destroyed=!0,this.loadTimers.forEach(e=>clearTimeout(e)),this.loadTimers.clear(),this.peripherals.destroy(),this.spineElement.replaceChildren(),this.bookElement.remove()}},Of=class{constructor(e,t,n,r){this.destroyed=!1,this.scrollRAF=0,this.restoreRAF=0,this.positionTimer=0,this.lastScrollTop=0,this.fraction=0,this.pageTops=[],this.pageHeights=[],this.stripHeightCached=0,this.viewportHeightCached=0,this.loadedIndices=new Set,this.lastWindowIndex=-1,this.programmaticScroll=!1,this.programmaticTimer=0,this.scrollTarget=null,this.animating=!1,this.animRAF=0,this.animLastTime=0,this.listener=()=>{},this.bscrollHandler=this.scrollHandler.bind(this),this.bscrollendHandler=this.scrollendHandler.bind(this),this.banimStep=this.animStep.bind(this),this.buserTakeoverHandler=this.userTakeoverHandler.bind(this),this.bmousedownHandler=this.mousedownHandler.bind(this),this.bclickHandler=this.clickHandler.bind(this),this.btouchendHandler=this.touchendHandler.bind(this),this.btouchstartHandler=this.touchstartHandler.bind(this),this.touchStartY=null,this.lastTouchEnd=0,this.mouseDownPos=null,this.container=e,this.spreader=t,this.pool=n,this.stripWidth=r,this.scrollerElement=document.createElement(`div`),this.scrollerElement.ariaLabel=`Book`,this.scrollerElement.tabIndex=-1,Object.assign(this.scrollerElement.style,{overflowY:`auto`,overflowX:`hidden`,height:`100%`,width:`100%`,position:`relative`,outline:`none`,overscrollBehavior:`contain`});let i=document.createDocumentFragment();this.spreader.pages.forEach(e=>{let t=this.pool.get(e.index);t.setMode(`scrolled`),t.wrapper.style.removeProperty(`contain`),i.appendChild(t.wrapper)}),this.scrollerElement.appendChild(i),this.container.appendChild(this.scrollerElement),this.applyStripWidth(r),this.scrollerElement.addEventListener(`scroll`,this.bscrollHandler,{passive:!0}),this.scrollerElement.addEventListener(`scrollend`,this.bscrollendHandler),this.scrollerElement.addEventListener(`wheel`,this.buserTakeoverHandler,{passive:!0}),this.scrollerElement.addEventListener(`mousedown`,this.bmousedownHandler),this.scrollerElement.addEventListener(`mouseup`,this.bclickHandler),this.scrollerElement.addEventListener(`touchend`,this.btouchendHandler),this.scrollerElement.addEventListener(`touchstart`,this.btouchstartHandler,{passive:!0})}get displayWidth(){return Math.max(1,Math.min(this.stripWidth,this.scrollerElement.clientWidth||this.container.clientWidth))}refreshLayoutCache(){this.viewportHeightCached=this.scrollerElement.clientHeight,this.stripHeightCached=this.scrollerElement.scrollHeight;let e=this.spreader.pages.length;this.pageTops=Array(e),this.pageHeights=Array(e);for(let e of this.spreader.pages){let t=this.pool.get(e.index).wrapper;this.pageTops[e.index]=t.offsetTop,this.pageHeights[e.index]=Math.max(1,t.offsetHeight)}}indexAtOffset(e){let t=this.pageTops,n=0,r=t.length-1,i=0;for(;n<=r;){let a=n+r>>1;t[a]<=e?(i=a,n=a+1):r=a-1}return i}applyStripWidth(e){this.stripWidth=e;let t=this.fraction,n=this.displayWidth;this.spreader.pages.forEach(e=>{this.pool.get(e.index)?.applyStripWidth(n)}),this.refreshLayoutCache(),this.restoreFraction(t)}restoreFraction(e){cancelAnimationFrame(this.restoreRAF),this.restoreRAF=requestAnimationFrame(()=>{if(this.destroyed)return;let t=e*this.stripHeightCached;Math.abs(this.scrollerElement.scrollTop-t)>=1&&(this.beginProgrammaticScroll(),this.scrollTarget=t,this.scrollerElement.scrollTop=t),this.updateFraction()})}updateFraction(){let e=this.stripHeightCached;this.fraction=e>0?this.scrollerElement.scrollTop/e:0}pageTop(e){return this.pageTops[e]??0}pageHeight(e){return this.pageHeights[e]??1}get currentIndex(){return this.pageTops.length?this.indexAtOffset(this.scrollerElement.scrollTop+this.viewportHeightCached*.5):0}get currentPageProgression(){let e=this.currentIndex;return Math.max(0,Math.min(1,(this.scrollerElement.scrollTop-this.pageTop(e))/this.pageHeight(e)))}beginProgrammaticScroll(){this.programmaticScroll=!0,window.clearTimeout(this.programmaticTimer),this.programmaticTimer=window.setTimeout(()=>{this.programmaticScroll=!1,this.scrollTarget=null,this.settleWindow()},1200)}scrollendHandler(){this.animating||(window.clearTimeout(this.programmaticTimer),this.programmaticScroll=!1,this.scrollTarget=null,this.settleWindow())}settleWindow(){if(this.destroyed||!this.pageTops.length)return;let e=this.currentIndex;this.lastWindowIndex=e,this.updateWindow(e)}userTakeoverHandler(){window.clearTimeout(this.programmaticTimer),this.programmaticScroll=!1,this.scrollTarget=null,this.stopAnimation()}scrollHandler(){this.destroyed||(cancelAnimationFrame(this.scrollRAF),this.scrollRAF=requestAnimationFrame(()=>{if(this.destroyed)return;let e=this.scrollerElement.scrollTop,t=e-this.lastScrollTop;this.lastScrollTop=e,Math.abs(this.scrollerElement.scrollHeight-this.stripHeightCached)>1&&this.refreshLayoutCache(),this.updateFraction(),!this.programmaticScroll&&t!==0&&this.listener(`scroll`,t);let n=this.currentIndex;n!==this.lastWindowIndex&&!this.programmaticScroll&&(this.lastWindowIndex=n,this.updateWindow(n)),window.clearTimeout(this.positionTimer),this.positionTimer=window.setTimeout(()=>{this.destroyed||this.listener(`position`,this.currentIndex)},150)}))}updateWindow(e){let t=this.spreader.pages.length;for(let n=Math.max(0,e-5);n<=Math.min(t-1,e+5);n++)this.pool.get(n)?.load(),this.loadedIndices.add(n);for(let t of this.loadedIndices)Math.abs(t-e)>10&&(this.pool.get(t)?.unload(),this.loadedIndices.delete(t))}touchstartHandler(e){this.userTakeoverHandler(),this.touchStartY=e.touches.length===1?e.touches[0].clientY:null}touchendHandler(e){if(this.touchStartY===null||e.changedTouches.length!==1)return;let t=Math.abs(e.changedTouches[0].clientY-this.touchStartY);this.touchStartY=null,t<=5&&(e.cancelable&&e.preventDefault(),this.lastTouchEnd=performance.now(),this.emitPointer(`tap`,e.changedTouches[0].clientX,e.changedTouches[0].clientY))}mousedownHandler(e){this.mouseDownPos=e.button===0?{x:e.clientX,y:e.clientY}:null}clickHandler(e){if(e.button!==0||this.mouseDownPos===null)return;let t=Math.abs(e.clientX-this.mouseDownPos.x)+Math.abs(e.clientY-this.mouseDownPos.y);this.mouseDownPos=null,!(performance.now()-this.lastTouchEnd<700)&&t<=5&&this.emitPointer(`click`,e.clientX,e.clientY)}emitPointer(e,t,n){let r=this.scrollerElement.getBoundingClientRect(),i=window.devicePixelRatio||1;this.listener(e,{x:(t-r.left)*i,y:(n-r.top)*i,clientX:t,clientY:n,doNotDisturb:!1})}next(e=!0,t){let n=this.scrollerElement.scrollHeight-this.scrollerElement.clientHeight,r=this.scrollTarget??this.scrollerElement.scrollTop;if(r>=n-1)return!1;let i=Math.min(r+(t??this.viewportHeightCached*.8),n);return e&&(i=Math.min(i,this.scrollerElement.scrollTop+this.viewportHeightCached*1.5)),this.scrollToTarget(i,e),!0}prev(e=!0,t){let n=this.scrollTarget??this.scrollerElement.scrollTop;if(n<=1)return!1;let r=Math.max(n-(t??this.viewportHeightCached*.8),0);return e&&(r=Math.max(r,this.scrollerElement.scrollTop-this.viewportHeightCached*1.5)),this.scrollToTarget(r,e),!0}scrollToTarget(e,t){this.beginProgrammaticScroll(),this.scrollTarget=e,t?this.animating||(this.animating=!0,this.animLastTime=performance.now(),this.animRAF=requestAnimationFrame(this.banimStep)):(this.stopAnimation(),this.scrollerElement.scrollTo({top:e,behavior:`auto`}))}animStep(e){if(this.destroyed)return;let t=this.scrollTarget;if(t===null){this.stopAnimation();return}let n=Math.min(Math.max(e-this.animLastTime,0)/1e3,.1);this.animLastTime=e;let r=this.scrollerElement,i=t-r.scrollTop;if(Math.abs(i)<=1){r.scrollTop=t,this.stopAnimation();return}let a=this.viewportHeightCached*8*n,o=i*Math.min(1,20*n);Math.abs(o)>a&&(o=Math.sign(i)*a),r.scrollTop+=o,this.animRAF=requestAnimationFrame(this.banimStep)}stopAnimation(){this.animating=!1,cancelAnimationFrame(this.animRAF)}goToItem(e,t=!1,n=0){cancelAnimationFrame(this.restoreRAF);let r=Math.max(0,Math.min(e,this.spreader.pages.length-1)),i=this.pageTop(r)+n*this.pageHeight(r);return Math.abs(this.scrollerElement.scrollTop-i)<1?!1:(this.scrollToTarget(i,t),t||this.updateFraction(),!0)}async update(){if(this.destroyed)return;let e=this.currentIndex;this.lastWindowIndex=e,this.updateWindow(e);let t=this.pool.get(e);t&&await t.load()}get atStart(){return this.scrollerElement.scrollTop<=1}get atEnd(){return this.scrollerElement.scrollTop>=this.stripHeightCached-this.viewportHeightCached-1}get viewport(){let e={readingOrder:[],progressions:new Map,positions:null};if(!this.pageTops.length)return e;let t=this.scrollerElement.scrollTop,n=t+this.viewportHeightCached,r=[];for(let i=this.indexAtOffset(t);i<this.spreader.pages.length;i++){let a=this.pageTop(i);if(a>=n)break;let o=this.pageHeight(i);if(a+o<=t)continue;let s=this.spreader.pages[i],c={start:Math.max(0,(t-a)/o),end:Math.min(1,(n-a)/o)};e.readingOrder.push(s.link.href),e.progressions.set(s.link.href,c),r.push(s.number)}return e.positions=r.length?r:null,e}resizeHandler(){let e=this.fraction,t=this.displayWidth;this.spreader.pages.forEach(e=>{this.pool.get(e.index)?.applyStripWidth(t)}),this.refreshLayoutCache(),this.restoreFraction(e)}async destroy(){this.destroyed=!0,cancelAnimationFrame(this.scrollRAF),cancelAnimationFrame(this.restoreRAF),cancelAnimationFrame(this.animRAF),window.clearTimeout(this.positionTimer),window.clearTimeout(this.programmaticTimer),this.scrollerElement.removeEventListener(`scroll`,this.bscrollHandler),this.scrollerElement.removeEventListener(`scrollend`,this.bscrollendHandler),this.scrollerElement.removeEventListener(`wheel`,this.buserTakeoverHandler),this.scrollerElement.removeEventListener(`mousedown`,this.bmousedownHandler),this.scrollerElement.removeEventListener(`mouseup`,this.bclickHandler),this.scrollerElement.removeEventListener(`touchend`,this.btouchendHandler),this.scrollerElement.removeEventListener(`touchstart`,this.btouchstartHandler),this.scrollerElement.replaceChildren(),this.scrollerElement.remove()}},kf=class{constructor(e={}){this.dragstartHandler=t=>{t.preventDefault(),t.stopPropagation(),e.onDragDetected?.(Array.from(t.dataTransfer?.types??[]))},this.dragoverHandler=e=>{e.preventDefault(),e.stopPropagation()},this.dropHandler=t=>{t.preventDefault(),t.stopPropagation();let n=Array.from(t.dataTransfer?.types??[]),r=t.dataTransfer?.files.length??0;e.onDropDetected?.(n,r)},this.unloadHandler=()=>this.destroy(),document.addEventListener(`dragstart`,this.dragstartHandler,!0),document.addEventListener(`dragover`,this.dragoverHandler,!0),document.addEventListener(`drop`,this.dropHandler,!0),window.addEventListener(`unload`,this.unloadHandler)}destroy(){document.removeEventListener(`dragstart`,this.dragstartHandler,!0),document.removeEventListener(`dragover`,this.dragoverHandler,!0),document.removeEventListener(`drop`,this.dropHandler,!0),window.removeEventListener(`unload`,this.unloadHandler)}},Af=class{constructor(e={}){this.copyHandler=t=>{t.preventDefault(),t.stopPropagation(),e.onCopyBlocked?.()},this.unloadHandler=()=>this.destroy(),document.addEventListener(`copy`,this.copyHandler,!0),window.addEventListener(`unload`,this.unloadHandler)}destroy(){document.removeEventListener(`copy`,this.copyHandler,!0),window.removeEventListener(`unload`,this.unloadHandler)}},jf=class extends uu{constructor(e={}){super(e),e.disableDragAndDrop&&(this.dragAndDropProtector=new kf({onDragDetected:e=>{this.dispatchSuspiciousActivity(`drag_detected`,{dataTransferTypes:e,targetFrameSrc:``})},onDropDetected:(e,t)=>{this.dispatchSuspiciousActivity(`drop_detected`,{dataTransferTypes:e,fileCount:t,targetFrameSrc:``})}})),e.protectCopy&&(this.copyProtector=new Af({onCopyBlocked:()=>{this.dispatchSuspiciousActivity(`bulk_copy`,{targetFrameSrc:``})}}))}destroy(){super.destroy(),this.dragAndDropProtector?.destroy(),this.copyProtector?.destroy()}},Mf={range:[480,2400],step:20},Nf=class e{constructor(e={}){this.backgroundColor=G(e.backgroundColor),this.constraint=q(e.constraint),this.quality=El(e.quality,ef),this.scrolled=K(e.scrolled),this.spreads=K(e.spreads),this.stripWidth=J(e.stripWidth,Mf.range)}static serialize(e){let{...t}=e;return JSON.stringify(t)}static deserialize(t){try{let n=JSON.parse(t);return new e(n)}catch(e){return console.error(`Failed to deserialize preferences:`,e),null}}merging(t){let n={...this};for(let e of Object.keys(t))t[e]!==void 0&&(n[e]=t[e]);return new e(n)}},Pf=class{constructor(e){this.backgroundColor=G(e.backgroundColor)||null,this.constraint=q(e.constraint)||0,this.quality=El(e.quality,ef)||ef.auto,this.scrolled=K(e.scrolled)??null,this.spreads=K(e.spreads)??!0,this.stripWidth=J(e.stripWidth,Mf.range)||720}},Ff=class{constructor(e,t,n){this.backgroundColor=e.backgroundColor??t.backgroundColor,this.constraint=e.constraint??t.constraint,this.quality=e.quality??t.quality,this.scrolled=n?!0:e.scrolled??t.scrolled??!1,this.spreads=e.spreads??t.spreads,this.stripWidth=e.stripWidth??t.stripWidth}},If=class{constructor(e,t,n){this.preferences=new Nf({...e}),this.settings=t,this.metadata=n}clear(){this.preferences=new Nf({backgroundColor:null,constraint:null,quality:null,scrolled:null,spreads:null,stripWidth:null})}updatePreference(e,t){this.preferences[e]=t}get manifestScrolled(){return this.metadata.effectiveLayout===D.scrolled}get backgroundColor(){return new Y({initialValue:this.preferences.backgroundColor,effectiveValue:this.settings.backgroundColor,isEffective:!0,onChange:e=>{this.updatePreference(`backgroundColor`,e??null)}})}get quality(){return new Nl({initialValue:this.preferences.quality,effectiveValue:this.settings.quality,isEffective:!0,onChange:e=>{this.updatePreference(`quality`,e??null)},supportedValues:[ef.auto,ef.low,ef.high,ef.max]})}get scrolled(){return new X({initialValue:this.preferences.scrolled,effectiveValue:this.settings.scrolled,isEffective:!this.manifestScrolled,onChange:e=>{this.updatePreference(`scrolled`,e??null)}})}get spreads(){return new X({initialValue:this.preferences.spreads,effectiveValue:this.settings.spreads,isEffective:!this.settings.scrolled,onChange:e=>{this.updatePreference(`spreads`,e??null)}})}get stripWidth(){return new Z({initialValue:this.preferences.stripWidth,effectiveValue:this.settings.stripWidth,isEffective:this.settings.scrolled,onChange:e=>{this.updatePreference(`stripWidth`,e??null)},supportedRange:Mf.range,step:Mf.step})}},Lf=e=>({positionChanged:e.positionChanged||(()=>{}),timelineItemChanged:e.timelineItemChanged||(()=>{}),tap:e.tap||(()=>!1),click:e.click||(()=>!1),zoom:e.zoom||(()=>{}),miscPointer:e.miscPointer||(()=>{}),scroll:e.scroll||(()=>{}),customEvent:e.customEvent||(()=>{}),handleLocator:e.handleLocator||(()=>!1),contentProtection:e.contentProtection||(()=>{}),contextMenu:e.contextMenu||(()=>{}),peripheral:e.peripheral||(()=>{})}),Rf=class extends Mc{constructor(e,t,n,r=[],i=void 0,a={preferences:{},defaults:{}}){super(),this._destroyed=!1,this._isNavigating=!1,this._timelineAugmented=!1,this._preferencesEditor=null,this.pool=new Map,this.pagedPresenter=null,this.scrolledPresenter=null,this._navigatorProtector=null,this._keyboardPeripheralsManager=null,this._keyboardConditionBridge=null,this._suspiciousActivityListener=null,this._keyboardPeripheralListener=null,this._applying=Promise.resolve(),this.pub=t,this.container=e,this.listeners=Lf(n),this.currentLocation=i,r.length&&(this.positions=r),this._preferences=new Nf(a.preferences),this._defaults=new Pf(a.defaults),this._settings=new Ff(this._preferences,this._defaults,this.manifestScrolled),this.spreader=new $d(t),this._contentProtection=a.contentProtection||{},this._keyboardPeripherals=this.mergeKeyboardPeripherals(this._contentProtection,a.keyboardPeripherals||[]),(this._contentProtection.disableContextMenu||this._contentProtection.checkAutomation||this._contentProtection.checkIFrameEmbedding||this._contentProtection.monitorDevTools||this._contentProtection.protectPrinting?.disable||this._contentProtection.disableDragAndDrop||this._contentProtection.protectCopy)&&(this._navigatorProtector=new jf(this._contentProtection),this._suspiciousActivityListener=e=>{let{type:t,...n}=e.detail;t===`context_menu`?this.listeners.contextMenu(n):this.listeners.contentProtection(t,n)},window.addEventListener(`readium:navigator:suspiciousActivity`,this._suspiciousActivityListener)),this._keyboardPeripherals.length>0&&(this._keyboardConditionBridge=new Wc(this._keyboardPeripherals,e=>{this._keyboardPeripheralsManager?.destroy(),this._keyboardPeripheralsManager=e.length>0?new fu({keyboardPeripherals:e}):null}),this._keyboardConditionBridge.setup(),this._keyboardPeripheralListener=e=>{let t=e.detail;this.listeners.peripheral(t)},window.addEventListener(`readium:navigator:keyboardPeripheral`,this._keyboardPeripheralListener)),this.resizeObserver=new ResizeObserver(()=>this.ownerWindow.requestAnimationFrame(()=>this.resizeHandler())),this.resizeObserver.observe(this.container.parentElement||document.documentElement)}get manifestScrolled(){return this.pub.metadata.effectiveLayout===D.scrolled}get ownerWindow(){return this.container.ownerDocument.defaultView||window}get publication(){return this.pub}get timeline(){let e=this.pub.timeline;if(!this._timelineAugmented&&this.positions?.length){let t=this.positions,n=new Set;e.augment((e,r)=>{if(e.children?.length||n.has(r.href))return{};let i=t.find(e=>e.href===r.href);return i?(n.add(r.href),{position:i.locations.position}):{}}),this._timelineAugmented=!0}return this._wrappedTimeline||=e,this._wrappedTimeline}_notifyTimelineChange(e){let t=this.timeline.locate(e);t!==this._currentTimelineItem&&(this._currentTimelineItem=t,this.listeners.timelineItemChanged(t))}get layout(){return this._settings.scrolled?D.scrolled:D.fixed}get readingProgression(){return this.pub.metadata.effectiveReadingProgression}get presenter(){return this.pagedPresenter??this.scrolledPresenter}async load(){if(this.positions?.length||(this.positions=await this.pub.positionsFromManifest()),this._destroyed)return;this.positions?.length||(this.positions=this.synthesizePositions());let e=async(e,t)=>{let n=this.pub.get(e),r=await n.read(void 0,{signal:t});if(!r)throw Error(`Empty resource: ${e.href}`);let i=await n.link(),a=i.type===void 0?e.mediaType:i.mediaType;return new Blob([r],{type:a.string})},t=()=>this._settings.quality;if(this.spreader.pages.forEach(n=>{this.pool.set(n.index,new ff(n,e,t))}),this.applyBackground(),this.createPresenter(),!this._destroyed)return this.resizeHandler(),this.currentLocation=this.currentLocation===void 0?this.positions[0]:this.completeLocator(this.currentLocation),new Promise(e=>{if(this._destroyed)return e(!1);this.go(this.currentLocation,!1,t=>e(t))})}synthesizePositions(){let e=this.pub.readingOrder.items.length;return this.pub.readingOrder.items.map((t,n)=>t.locator.copyWithLocations({progression:0,position:n+1,totalProgression:e>0?n/e:0}))}createPresenter(){this._settings.scrolled?(this.scrolledPresenter=new Of(this.container,this.spreader,this.pool,this._settings.stripWidth),this.scrolledPresenter.listener=(e,t)=>{switch(e){case`scroll`:this.listeners.scroll(t);break;case`position`:this.updateLocationFromScroll(t);break;case`tap`:case`click`:this.handlePointer(e,t)}}):(this.pagedPresenter=new Df(this.container,this.pub,this.spreader,this.pool,this._settings.spreads),this.pagedPresenter.listener=(e,t)=>{switch(e){case`no_more`:this.changeSpread(1);break;case`no_less`:this.changeSpread(-1);break;case`zoom`:this.listeners.zoom(t);break;case`tap`:case`click`:this.handlePointer(e,t)}})}async destroyPresenter(){this.pagedPresenter&&=(await this.pagedPresenter.destroy(),null),this.scrolledPresenter&&=(await this.scrolledPresenter.destroy(),null)}handlePointer(e,t){let n={defaultPrevented:!1,doNotDisturb:t.doNotDisturb,interactiveElement:void 0,cssSelector:void 0,targetElement:``,targetFrameSrc:``,x:t.x,y:t.y};if((e===`click`?this.listeners.click(n):this.listeners.tap(n))||t.doNotDisturb)return;let r=window.devicePixelRatio||1;if(this._settings.scrolled){let e=this.container.clientHeight*r/4;t.y>=e&&t.y<=e*3?this.listeners.miscPointer(1):t.y<e?this.goBackward(!0,()=>{}):this.goForward(!0,()=>{})}else{let e=this.container.clientWidth*r/4;t.x>=e&&t.x<=e*3?this.listeners.miscPointer(1):t.x<e?this.goLeft(!1,()=>{}):this.goRight(!1,()=>{})}}changeSpread(e){let t=this.pagedPresenter;return!t||!(e>0?t.next():t.prev())?!1:(this.setLocationToIndex(t.currentIndex),t.update(),this.listeners.positionChanged(this.currentLocation),this._notifyTimelineChange(this.currentLocation),!0)}setLocationToIndex(e){let t=this.pub.readingOrder.items[e];if(!t)return;let n=this.positions.find(e=>e.href===t.href);this.currentLocation=n??this.synthesizePositions()[e]}updateLocationFromScroll(e){let t=this.scrolledPresenter;if(!t)return;this.setLocationToIndex(e);let n=this.pub.readingOrder.items.length,r=t.currentPageProgression;this.currentLocation=this.currentLocation.copyWithLocations({progression:r,totalProgression:n>0?Math.min((e+r)/n,1):0}),this.listeners.positionChanged(this.currentLocation),this._notifyTimelineChange(this.currentLocation)}applyBackground(){let e=this._settings.backgroundColor;if(e){this.container.style.background=e;let t=this.isDarkColor(e);t===null?(this.container.style.removeProperty(`color-scheme`),this.container.style.removeProperty(`scrollbar-color`)):(this.container.style.colorScheme=t?`dark`:`light`,this.container.style.scrollbarColor=`${t?`rgba(255, 255, 255, 0.3)`:`rgba(0, 0, 0, 0.3)`} ${e}`)}else this.container.style.removeProperty(`background`),this.container.style.removeProperty(`color-scheme`),this.container.style.removeProperty(`scrollbar-color`)}isDarkColor(e){let t=this.container.ownerDocument,n=t.createElement(`div`);n.style.display=`none`,n.style.color=e,t.body.appendChild(n);let r=(t.defaultView||window).getComputedStyle(n).color;n.remove();let i=r.match(/rgba?\(\s*(\d+)[,\s]+(\d+)[,\s]+(\d+)/);return i?(.2126*i[1]+.7152*i[2]+.0722*i[3])/255<.45:null}resizeHandler(){let e=this.container.parentElement||document.documentElement,t=window.devicePixelRatio||1,n=Math.floor((Yu(e)-this._settings.constraint)*t)/t;Q()?this.container.attributeStyleMap.set(`width`,CSS.px(n)):this.container.style.width=`${n}px`,this.pagedPresenter?.resizeHandler(),this.scrolledPresenter?.resizeHandler()}completeLocator(e){if(!e.href){let t=!1;if(typeof e.locations.position==`number`){let n=this.positions.find(t=>t.locations.position===e.locations.position);n&&(e=n.copyWithLocations(e.locations),t=!0)}if(!t&&typeof e.locations?.totalProgression==`number`){let t=e.locations.totalProgression,n=0,r=1/0;for(let e=0;e<this.positions.length;e++){let i=this.positions[e].locations.totalProgression??e/this.positions.length,a=Math.abs(i-t);a<r&&(r=a,n=e)}e=this.positions[n].copyWithLocations(e.locations)}}return e}findReadingOrderIndex(e){let t=this.pub.readingOrder.findIndexWithHref(e);if(t>=0)return t;let n=this.pub.baseURL,r=new M({href:e}).toURL(n)??e,i=e=>(e.toURL(n)??e.href)===r;return this.pub.readingOrder.items.findIndex(e=>i(e)||!!e.alternates?.items.some(i))}go(e,t,n){e=this.completeLocator(e);let r=e.href?.split(`#`)[0],i=r?this.findReadingOrderIndex(r):-1;if(i<0)return n(this.listeners.handleLocator(e));if(this._isNavigating)n(!1);else{this._isNavigating=!0;try{if(this.scrolledPresenter){let n=e.locations?.progression||0;this.scrolledPresenter.goToItem(i,t,n),this.scrolledPresenter.update()}else this.pagedPresenter&&(this.pagedPresenter.goToItem(i,t),this.pagedPresenter.update());this.setLocationToIndex(this.pagedPresenter?this.pagedPresenter.currentIndex:i),this.listeners.positionChanged(this.currentLocation),this._notifyTimelineChange(this.currentLocation),n(!0)}finally{this._isNavigating=!1}}}goLink(e,t,n){return this.go(e.locator,t,n)}goForward(e,t){this.scrolledPresenter?t(this.scrolledPresenter.next(e)):t(this.changeSpread(1))}goBackward(e,t){this.scrolledPresenter?t(this.scrolledPresenter.prev(e)):t(this.changeSpread(-1))}scrollBy(e,t,n){this.scrolledPresenter?n(e>=0?this.scrolledPresenter.next(t,e):this.scrolledPresenter.prev(t,-e)):n(this.changeSpread(e>=0?1:-1))}zoomIn(){this.pagedPresenter?.peripherals.zoomIn()}zoomOut(){this.pagedPresenter?.peripherals.zoomOut()}zoomReset(){this.pagedPresenter?.peripherals.resetZoom()}get currentLocator(){return this.currentLocation}get viewport(){return this.presenter?.viewport??{readingOrder:[],progressions:new Map,positions:null}}get isScrollStart(){let e=this.viewport.readingOrder[0];return(e?this.viewport.progressions.get(e):void 0)?.start===0}get isScrollEnd(){let e=this.viewport.readingOrder[this.viewport.readingOrder.length-1];return(e?this.viewport.progressions.get(e):void 0)?.end===1}get canGoBackward(){let e=this.pub.readingOrder.items[0]?.href;return!(this.viewport.progressions.has(e)&&this.viewport.progressions.get(e)?.start===0)}get canGoForward(){let e=this.pub.readingOrder.items[this.pub.readingOrder.items.length-1]?.href;return!(this.viewport.progressions.has(e)&&this.viewport.progressions.get(e)?.end===1)}get settings(){return Object.freeze({...this._settings})}get preferencesEditor(){return this._preferencesEditor===null&&(this._preferencesEditor=new If(this._preferences,this.settings,this.pub.metadata)),this._preferencesEditor}async submitPreferences(e){this._preferences=this._preferences.merging(e),this._applying=this._applying.then(()=>this.applyPreferences()),await this._applying}async applyPreferences(){let e=this._settings;if(this._settings=new Ff(this._preferences,this._defaults,this.manifestScrolled),this._preferencesEditor!==null&&(this._preferencesEditor=new If(this._preferences,this.settings,this.pub.metadata)),e.backgroundColor!==this._settings.backgroundColor&&this.applyBackground(),e.constraint!==this._settings.constraint&&this.resizeHandler(),e.scrolled!==this._settings.scrolled){if(!this.presenter)return;let e=this.currentLocation;if(await this.destroyPresenter(),this._destroyed)return;this.createPresenter(),this.resizeHandler(),this.go(e,!1,()=>{})}else e.spreads!==this._settings.spreads&&this.pagedPresenter?.setSpreads(this._settings.spreads),e.stripWidth!==this._settings.stripWidth&&this.scrolledPresenter?.applyStripWidth(this._settings.stripWidth),e.quality!==this._settings.quality&&(this.pool.forEach(e=>e.unload()),this.pagedPresenter?.update(),this.scrolledPresenter?.update())}async destroy(){this._destroyed=!0,this._suspiciousActivityListener&&window.removeEventListener(`readium:navigator:suspiciousActivity`,this._suspiciousActivityListener),this._keyboardPeripheralListener&&window.removeEventListener(`readium:navigator:keyboardPeripheral`,this._keyboardPeripheralListener),this._navigatorProtector?.destroy(),this._keyboardConditionBridge?.destroy(),this._keyboardPeripheralsManager?.destroy(),this.resizeObserver.disconnect(),await this.destroyPresenter(),this.pool.forEach(e=>e.destroy()),this.pool.clear(),Array.from(this.container.childNodes).forEach(e=>{(e.nodeType===Node.ELEMENT_NODE||e.nodeType===Node.TEXT_NODE)&&e.remove()})}},zf=`// PreservePitchProcessor.js
// AudioWorklet processor for pitch preservation via pitch shifting.
//
// Architecture:
//   - Overlap-add (OLA) phase vocoder with an iterative in-place Cooley-Tukey FFT/IFFT.
//   - All intermediate buffers are pre-allocated in the constructor; the hot path
//     (process → _processBuffer → _fft) is allocation-free and GC-safe.
//   - An output ring buffer decouples OLA processing (fires every hopSize input
//     samples) from the Web Audio render quantum (128 frames), so process() always
//     fills outputChannel completely.

class PreservePitchProcessor extends AudioWorkletProcessor {
  constructor() {
    super();
    this.bufferSize  = 1024;
    this.hopSize     = 256;
    this.overlap     = this.bufferSize - this.hopSize;
    this.pitchFactor = 1.0;

    // Sliding input window (always holds the last bufferSize samples)
    this.inputBuffer = new Float32Array(this.bufferSize);
    this.inputFill   = 0;   // samples loaded during startup (saturates at bufferSize)
    this.hopAccum    = 0;   // new samples since last OLA step; triggers a step at hopSize

    // OLA output accumulator: overlap-add results accumulate here; hopSize samples
    // are drained to the ring buffer and the remainder shifts down each OLA step.
    this.olaBuffer = new Float32Array(this.bufferSize);

    // Output FIFO ring buffer — power-of-2 size for allocation-free modulo wrapping.
    this._ringSize  = 4096;
    this._ring      = new Float32Array(this._ringSize);
    this._ringMask  = this._ringSize - 1;
    this._ringWrite = 0;
    this._ringRead  = 0;
    this._ringAvail = 0;

    // Hann window (pre-computed, never mutated)
    this.window = new Float32Array(this.bufferSize);
    for (let i = 0; i < this.bufferSize; i++) {
      this.window[i] = 0.5 * (1 - Math.cos(2 * Math.PI * i / this.bufferSize));
    }

    // Pre-allocated FFT work buffers — never re-created in the hot path
    this._re        = new Float64Array(this.bufferSize);
    this._im        = new Float64Array(this.bufferSize);
    this._shiftedRe = new Float64Array(this.bufferSize);
    this._shiftedIm = new Float64Array(this.bufferSize);

    this.port.onmessage = (event) => {
      if (event.data.type === 'setPitchFactor') {
        this.pitchFactor = event.data.factor;
      }
    };
  }

  process(inputs, outputs) {
    const input  = inputs[0];
    const output = outputs[0];
    if (!input || !output) return true;
    const inCh  = input[0];
    const outCh = output[0];
    if (!inCh || !outCh) return true;

    const newCount = inCh.length; // always 128 under normal Web Audio conditions

    // --- 1. Push new samples into the sliding input window ---
    if (this.inputFill < this.bufferSize) {
      // Startup: fill the window until we have a full bufferSize frame.
      // Since bufferSize (1024) is an exact multiple of the render quantum (128)
      // this branch always copies exactly newCount samples.
      this.inputBuffer.set(inCh, this.inputFill);
      this.inputFill += newCount;
    } else {
      // Steady state: slide left by newCount, append the new quantum at the end.
      this.inputBuffer.copyWithin(0, newCount);
      this.inputBuffer.set(inCh, this.bufferSize - newCount);
    }
    this.hopAccum += newCount;

    // --- 2. Run OLA step(s) whenever hopAccum reaches hopSize ---
    // During startup we skip processing until a full window is available.
    while (this.inputFill >= this.bufferSize && this.hopAccum >= this.hopSize) {
      this.hopAccum -= this.hopSize;
      this._processBuffer(); // drains hopSize samples into _ring
    }

    // --- 3. Drain output ring into outputChannel ---
    // Output silence during the initial buffering latency (bufferSize samples ≈ 23 ms
    // at 44100 Hz).  Once the ring has data it stays ahead of demand.
    if (this._ringAvail >= newCount) {
      for (let i = 0; i < newCount; i++) {
        outCh[i] = this._ring[this._ringRead];
        this._ringRead = (this._ringRead + 1) & this._ringMask;
      }
      this._ringAvail -= newCount;
    } else {
      outCh.fill(0);
    }

    return true;
  }

  _processBuffer() {
    const N         = this.bufferSize;
    const re        = this._re;
    const im        = this._im;
    const shiftedRe = this._shiftedRe;
    const shiftedIm = this._shiftedIm;
    const win       = this.window;

    // Load windowed input into real part; zero imaginary part
    for (let i = 0; i < N; i++) {
      re[i] = this.inputBuffer[i] * win[i];
      im[i] = 0;
    }

    this._fft(re, im, false);

    // Spectral pitch shift: map bin k → round(k * factor)
    shiftedRe.fill(0);
    shiftedIm.fill(0);
    const half   = N >> 1;
    const factor = this.pitchFactor;
    for (let k = 0; k <= half; k++) {
      const newK = Math.round(k * factor);
      if (newK <= half) {
        shiftedRe[newK] += re[k];
        shiftedIm[newK] += im[k];
        // Restore conjugate symmetry so the IFFT yields a real-valued signal
        if (newK > 0 && newK < half) {
          shiftedRe[N - newK] =  shiftedRe[newK];
          shiftedIm[N - newK] = -shiftedIm[newK];
        }
      }
    }

    this._fft(shiftedRe, shiftedIm, true); // in-place IFFT

    // Overlap-add into olaBuffer
    for (let i = 0; i < N; i++) {
      this.olaBuffer[i] += shiftedRe[i] * win[i];
    }

    // Push hopSize output samples to the ring buffer
    for (let i = 0; i < this.hopSize; i++) {
      this._ring[this._ringWrite] = this.olaBuffer[i];
      this._ringWrite = (this._ringWrite + 1) & this._ringMask;
    }
    this._ringAvail += this.hopSize;

    // Shift the OLA accumulator left by hopSize; clear the vacated tail
    this.olaBuffer.copyWithin(0, this.hopSize);
    this.olaBuffer.fill(0, this.bufferSize - this.hopSize);
  }

  /**
   * In-place iterative Cooley-Tukey FFT / IFFT.
   * Operates entirely on the caller-supplied Float64Arrays — no allocation.
   *
   * @param {Float64Array} re      Real parts (mutated in place)
   * @param {Float64Array} im      Imaginary parts (mutated in place)
   * @param {boolean}      inverse true → IFFT (divides by N), false → FFT
   */
  _fft(re, im, inverse) {
    const N = re.length;

    // Bit-reversal permutation
    let j = 0;
    for (let i = 1; i < N; i++) {
      let bit = N >> 1;
      for (; j & bit; bit >>= 1) j ^= bit;
      j ^= bit;
      if (i < j) {
        let tmp;
        tmp = re[i]; re[i] = re[j]; re[j] = tmp;
        tmp = im[i]; im[i] = im[j]; im[j] = tmp;
      }
    }

    // Butterfly stages — O(N log N), no allocation
    const sign = inverse ? 1 : -1;
    for (let len = 2; len <= N; len <<= 1) {
      const halfLen = len >> 1;
      const ang     = sign * Math.PI / halfLen;
      const wBaseRe = Math.cos(ang);
      const wBaseIm = Math.sin(ang);
      for (let i = 0; i < N; i += len) {
        let wRe = 1, wIm = 0;
        for (let k = 0; k < halfLen; k++) {
          const uRe = re[i + k];
          const uIm = im[i + k];
          const vRe = re[i + k + halfLen] * wRe - im[i + k + halfLen] * wIm;
          const vIm = re[i + k + halfLen] * wIm + im[i + k + halfLen] * wRe;
          re[i + k]           = uRe + vRe;
          im[i + k]           = uIm + vIm;
          re[i + k + halfLen] = uRe - vRe;
          im[i + k + halfLen] = uIm - vIm;
          const newWRe = wRe * wBaseRe - wIm * wBaseIm;
          wIm = wRe * wBaseIm + wIm * wBaseRe;
          wRe = newWRe;
        }
      }
    }

    if (inverse) {
      for (let i = 0; i < N; i++) {
        re[i] /= N;
        im[i] /= N;
      }
    }
  }
}

registerProcessor('preserve-pitch-processor', PreservePitchProcessor);
`,Bf=class e{constructor(e){this.workletNode=null,this.url=null,this.ctx=e}static async createWorklet(t){let{ctx:n,pitchFactor:r,modulePath:i}=t,a=new e(n);try{if(i)await n.audioWorklet.addModule(i);else{let e=new Blob([zf],{type:`text/javascript`});a.url=URL.createObjectURL(e),await n.audioWorklet.addModule(a.url)}}catch(e){throw a.destroy(),Error(`Error adding module: ${e}`)}try{a.workletNode=new AudioWorkletNode(n,`preserve-pitch-processor`),r&&a.updatePitchFactor(r)}catch(e){throw a.destroy(),Error(`Error creating worklet node: ${e}`)}return a}updatePitchFactor(e){this.workletNode&&this.workletNode.port.postMessage({type:`setPitchFactor`,factor:e})}destroy(){this.workletNode&&=(this.workletNode.disconnect(),null),this.url&&=(URL.revokeObjectURL(this.url),null)}},Vf=class{constructor(e){this.audioContext=null,this.sourceNode=null,this.gainNode=null,this.listeners={},this.isMutedValue=!1,this.isPlayingValue=!1,this.isPausedValue=!1,this.isLoadingValue=!1,this.isLoadedValue=!1,this.isEndedValue=!1,this.isStoppedValue=!1,this.worklet=null,this.webAudioActive=!1,this.mseLoader=null,this.currentHref=``,this.boundOnCanPlayThrough=this.onCanPlayThrough.bind(this),this.boundOnTimeUpdate=this.onTimeUpdate.bind(this),this.boundOnError=this.onError.bind(this),this.boundOnEnded=this.onEnded.bind(this),this.boundOnStalled=this.onStalled.bind(this),this.boundOnEmptied=this.onEmptied.bind(this),this.boundOnSuspend=this.onSuspend.bind(this),this.boundOnWaiting=this.onWaiting.bind(this),this.boundOnLoadedMetadata=this.onLoadedMetadata.bind(this),this.boundOnSeeking=this.onSeeking.bind(this),this.boundOnSeeked=this.onSeeked.bind(this),this.boundOnPlay=this.onPlay.bind(this),this.boundOnPlaying=this.onPlaying.bind(this),this.boundOnPause=this.onPause.bind(this),this.boundOnProgress=this.onProgress.bind(this),this.playback=e.playback,this.mseLoaderFactory=e.mseLoaderFactory??null,this.mediaElement=document.createElement(`audio`),this.mediaElement.addEventListener(`canplaythrough`,this.boundOnCanPlayThrough),this.mediaElement.addEventListener(`timeupdate`,this.boundOnTimeUpdate),this.mediaElement.addEventListener(`error`,this.boundOnError),this.mediaElement.addEventListener(`ended`,this.boundOnEnded),this.mediaElement.addEventListener(`stalled`,this.boundOnStalled),this.mediaElement.addEventListener(`emptied`,this.boundOnEmptied),this.mediaElement.addEventListener(`suspend`,this.boundOnSuspend),this.mediaElement.addEventListener(`waiting`,this.boundOnWaiting),this.mediaElement.addEventListener(`loadedmetadata`,this.boundOnLoadedMetadata),this.mediaElement.addEventListener(`seeking`,this.boundOnSeeking),this.mediaElement.addEventListener(`seeked`,this.boundOnSeeked),this.mediaElement.addEventListener(`play`,this.boundOnPlay),this.mediaElement.addEventListener(`playing`,this.boundOnPlaying),this.mediaElement.addEventListener(`pause`,this.boundOnPause),this.mediaElement.addEventListener(`progress`,this.boundOnProgress),this.mediaElement.currentTime=this.playback.state.currentTime}on(e,t){this.listeners[e]||(this.listeners[e]=[]),this.listeners[e].push(t)}off(e,t){this.listeners[e]&&(this.listeners[e]=this.listeners[e].filter(e=>e!==t))}async ensureAudioContextRunning(){this.audioContext||=new AudioContext,this.audioContext.state===`suspended`&&await this.audioContext.resume()}getOrCreateAudioContext(){return this.audioContext||=new AudioContext,this.audioContext}onTimeUpdate(){this.emit(`timeupdate`,this.mediaElement.currentTime)}onCanPlayThrough(){this.isLoadingValue=!1,this.isLoadedValue=!0,this.emit(`canplaythrough`,null)}onError(){console.error(`Error loading media element`),this.emit(`error`,this.mediaElement.error)}onEnded(){this.isPlayingValue=!1,this.isPausedValue=!1,this.isEndedValue=!0,this.emit(`ended`,null)}onStalled(e){this.emit(`stalled`,e)}onEmptied(e){this.emit(`emptied`,e)}onSuspend(e){this.emit(`suspend`,e)}onWaiting(e){this.emit(`waiting`,e)}onLoadedMetadata(e){this.emit(`loadedmetadata`,e)}onSeeking(e){this.emit(`seeking`,e)}onSeeked(e){this.emit(`seeked`,e)}onPlay(){this.emit(`play`,null)}onPlaying(){this.emit(`playing`,null)}onPause(){this.emit(`pause`,null)}onProgress(){this.emit(`progress`,this.mediaElement.seekable)}emit(e,t){this.listeners[e]&&this.listeners[e].forEach(e=>e(t))}async play(){if(!this.isPlayingValue)try{this.audioContext&&await this.ensureAudioContextRunning(),await this.mediaElement.play(),this.isPlayingValue=!0,this.isPausedValue=!1,this.isStoppedValue=!1}catch(e){if(e?.name===`AbortError`)return;console.error(`error trying to play media element`,e),this.emit(`error`,e)}}pause(){this.mediaElement.pause(),this.isPlayingValue=!1,this.isPausedValue=!0}stop(){this.mediaElement.pause(),this.mediaElement.currentTime=0,this.isPlayingValue=!1,this.isPausedValue=!1,this.isStoppedValue=!0}setVolume(e){let t=Math.max(0,Math.min(1,e));this.gainNode?(this.mediaElement.volume=1,this.gainNode.gain.value=t):this.mediaElement.volume=t,this.isMutedValue=t===0}skip(e){let t=this.mediaElement.duration;if(!isFinite(t))return;let n=this.mediaElement.currentTime+e;n<0?this.mediaElement.currentTime=0:n>t?this.mediaElement.currentTime=t:this.mediaElement.currentTime=n}currentTime(){return this.mediaElement.currentTime}duration(){return this.mediaElement.duration}isPlaying(){return this.isPlayingValue}isPaused(){return this.isPausedValue}isStopped(){return this.isStoppedValue}isLoading(){return this.isLoadingValue}isLoaded(){return this.isLoadedValue}isEnded(){return this.isEndedValue}isMuted(){return this.isMutedValue}setPlaybackRate(e,t){this.mediaElement.playbackRate=e,t?`preservesPitch`in this.mediaElement?this.mediaElement.preservesPitch=!0:this.activateWebAudio().then(()=>{this.worklet?this.worklet.updatePitchFactor(1/e):Bf.createWorklet({ctx:this.getOrCreateAudioContext(),pitchFactor:1}).then(t=>{this.sourceNode&&this.sourceNode.disconnect(),this.worklet=t,this.sourceNode?.connect(this.worklet.workletNode),this.worklet.workletNode.connect(this.gainNode),this.worklet.updatePitchFactor(1/e)}).catch(e=>{console.warn(`Failed to create preserve pitch worklet`,e)})}).catch(e=>{console.warn(`Web Audio unavailable, playing without pitch correction:`,e)}):(`preservesPitch`in this.mediaElement&&(this.mediaElement.preservesPitch=!1),this.worklet&&(this.worklet.destroy(),this.worklet=null,this.webAudioActive&&this.sourceNode&&(this.sourceNode.disconnect(),this.sourceNode.connect(this.gainNode))))}async activateWebAudio(){if(this.webAudioActive)return;if(this.usesMse){this.sourceNode=new MediaElementAudioSourceNode(this.getOrCreateAudioContext(),{mediaElement:this.mediaElement});let e=this.getOrCreateAudioContext();this.gainNode=e.createGain(),this.gainNode.gain.value=this.mediaElement.volume,this.mediaElement.volume=1,this.sourceNode.connect(this.gainNode),this.gainNode.connect(e.destination),this.webAudioActive=!0;return}let e=this.mediaElement.src;if(!e)return;let t=this.mediaElement.currentTime,n=this.isPlayingValue;n&&(this.mediaElement.pause(),this.isPlayingValue=!1),this.mediaElement.crossOrigin=`anonymous`,this.mediaElement.src=e,this.mediaElement.load();try{await new Promise((e,t)=>{let n=()=>{this.mediaElement.removeEventListener(`canplaythrough`,n),this.mediaElement.removeEventListener(`error`,r),e()},r=()=>{this.mediaElement.removeEventListener(`canplaythrough`,n),this.mediaElement.removeEventListener(`error`,r),t(Error(`Audio reload with CORS failed — server may not send Access-Control-Allow-Origin`))};this.mediaElement.addEventListener(`canplaythrough`,n),this.mediaElement.addEventListener(`error`,r)})}catch(r){throw this.mediaElement.removeAttribute(`crossorigin`),this.mediaElement.src=e,this.mediaElement.load(),n?(await new Promise(e=>{let t=()=>{this.mediaElement.removeEventListener(`canplaythrough`,t),e()};this.mediaElement.addEventListener(`canplaythrough`,t)}),this.mediaElement.currentTime=t,await this.mediaElement.play(),this.isPlayingValue=!0,this.isPausedValue=!1):this.mediaElement.currentTime=t,r}this.mediaElement.currentTime=t,this.sourceNode=new MediaElementAudioSourceNode(this.getOrCreateAudioContext(),{mediaElement:this.mediaElement});let r=this.getOrCreateAudioContext();this.gainNode=r.createGain(),this.gainNode.gain.value=this.mediaElement.volume,this.mediaElement.volume=1,this.sourceNode.connect(this.gainNode),this.gainNode.connect(r.destination),this.webAudioActive=!0,n&&(await this.ensureAudioContextRunning(),await this.mediaElement.play(),this.isPlayingValue=!0,this.isPausedValue=!1)}get isWebAudioActive(){return this.webAudioActive}get usesMse(){return this.mseLoaderFactory!==null}tearDownWebAudio(){this.worklet&&=(this.worklet.destroy(),null),this.sourceNode&&=(this.sourceNode.disconnect(),null),this.gainNode&&=(this.mediaElement.volume=this.gainNode.gain.value,this.gainNode.disconnect(),null),this.webAudioActive=!1}changeSrc(e,t){if(this.currentHref!==e&&this.mediaElement.src!==e){if(this.currentHref=e,this.mediaElement.pause(),this.isPlayingValue=!1,this.isPausedValue=!1,this.isLoadedValue=!1,this.isLoadingValue=!0,this.isEndedValue=!1,this.mseLoaderFactory){this.mseLoader?.destroy(),this.mseLoader=this.mseLoaderFactory(this.mediaElement,e,t),this.mseLoader.start();return}if(this.webAudioActive){this.mediaElement.crossOrigin=`anonymous`,this.mediaElement.src=e,this.mediaElement.load();let t=()=>{r()},n=()=>{r(),console.warn(`CORS reload failed for new track — disabling Web Audio graph:`,e),this.tearDownWebAudio(),this.mediaElement.removeAttribute(`crossorigin`),this.mediaElement.src=e,this.mediaElement.load()},r=()=>{this.mediaElement.removeEventListener(`canplaythrough`,t),this.mediaElement.removeEventListener(`error`,n)};this.mediaElement.addEventListener(`canplaythrough`,t),this.mediaElement.addEventListener(`error`,n)}else this.mediaElement.src=e,this.mediaElement.load()}}getMediaElement(){return this.mediaElement}destroy(){this.mseLoader?.destroy(),this.mseLoader=null}},Hf=class e{constructor(e={}){this.volume=J(e.volume,_l.range),this.playbackRate=J(e.playbackRate,vl.range),this.preservePitch=K(e.preservePitch),this.skipBackwardInterval=J(e.skipBackwardInterval,yl.range),this.skipForwardInterval=J(e.skipForwardInterval,yl.range),this.pollInterval=q(e.pollInterval),this.autoPlay=K(e.autoPlay),this.enableMediaSession=K(e.enableMediaSession)}merging(t){let n={...this};for(let e of Object.keys(t))t[e]!==void 0&&(n[e]=t[e]);return new e(n)}},Uf=class{constructor(e={}){this.volume=J(e.volume,_l.range)??1,this.playbackRate=J(e.playbackRate,vl.range)??1,this.preservePitch=K(e.preservePitch)??!0,this.skipBackwardInterval=J(e.skipBackwardInterval,yl.range)??10,this.skipForwardInterval=J(e.skipForwardInterval,yl.range)??10,this.pollInterval=q(e.pollInterval)??1e3,this.autoPlay=K(e.autoPlay)??!0,this.enableMediaSession=K(e.enableMediaSession)??!0}},Wf=class{constructor(e,t){this.volume=e.volume??t.volume,this.playbackRate=e.playbackRate??t.playbackRate,this.preservePitch=e.preservePitch??t.preservePitch,this.skipBackwardInterval=e.skipBackwardInterval??t.skipBackwardInterval,this.skipForwardInterval=e.skipForwardInterval??t.skipForwardInterval,this.pollInterval=e.pollInterval??t.pollInterval,this.autoPlay=e.autoPlay??t.autoPlay,this.enableMediaSession=e.enableMediaSession??t.enableMediaSession}},Gf=class{constructor(e,t){this.preferences=new Hf({...e}),this.settings=t}clear(){this.preferences=new Hf({volume:null,playbackRate:null,preservePitch:null,skipBackwardInterval:null,skipForwardInterval:null,pollInterval:null,autoPlay:null,enableMediaSession:null})}updatePreference(e,t){this.preferences[e]=t}get volume(){return new Z({initialValue:this.preferences.volume,effectiveValue:this.settings.volume,isEffective:this.preferences.volume!==null,onChange:e=>{this.updatePreference(`volume`,e??null)},supportedRange:_l.range,step:_l.step})}get playbackRate(){return new Z({initialValue:this.preferences.playbackRate,effectiveValue:this.settings.playbackRate,isEffective:this.preferences.playbackRate!==null,onChange:e=>{this.updatePreference(`playbackRate`,e??null)},supportedRange:vl.range,step:vl.step})}get preservePitch(){return new X({initialValue:this.preferences.preservePitch,effectiveValue:this.settings.preservePitch,isEffective:this.preferences.preservePitch!==null,onChange:e=>{this.updatePreference(`preservePitch`,e??null)}})}get skipBackwardInterval(){return new Z({initialValue:this.preferences.skipBackwardInterval,effectiveValue:this.settings.skipBackwardInterval,isEffective:this.preferences.skipBackwardInterval!==null,onChange:e=>{this.updatePreference(`skipBackwardInterval`,e??null)},supportedRange:yl.range,step:yl.step})}get skipForwardInterval(){return new Z({initialValue:this.preferences.skipForwardInterval,effectiveValue:this.settings.skipForwardInterval,isEffective:this.preferences.skipForwardInterval!==null,onChange:e=>{this.updatePreference(`skipForwardInterval`,e??null)},supportedRange:yl.range,step:yl.step})}get pollInterval(){return new Y({initialValue:this.preferences.pollInterval,effectiveValue:this.settings.pollInterval,isEffective:this.preferences.pollInterval!==null,onChange:e=>{this.updatePreference(`pollInterval`,e??null)}})}get autoPlay(){return new X({initialValue:this.preferences.autoPlay,effectiveValue:this.settings.autoPlay,isEffective:this.preferences.autoPlay!==null,onChange:e=>{this.updatePreference(`autoPlay`,e??null)}})}get enableMediaSession(){return new X({initialValue:this.preferences.enableMediaSession,effectiveValue:this.settings.enableMediaSession,isEffective:this.preferences.enableMediaSession!==null,onChange:e=>{this.updatePreference(`enableMediaSession`,e??null)}})}},Kf=class{constructor(e,t,n={}){this.pool=new Map,this._audioEngine=e,this._publication=t,this._supportedAudioTypes=this.detectSupportedAudioTypes(),n.disableRemotePlayback&&(this._audioEngine.getMediaElement().disableRemotePlayback=!0)}detectSupportedAudioTypes(){let e=document.createElement(`audio`),t=new Set;for(let e of this._publication.readingOrder.items){e.type&&t.add(e.type);for(let n of e.alternates?.items??[])n.type&&t.add(n.type)}let n=new Map;for(let r of t){let t=e.canPlayType(r);t!==``&&n.set(r,t)}return n}pickPlayableHref(e){let t=this._publication.baseURL,n=[e,...e.alternates?.items??[]],r;for(let e of n){if(!e.type)continue;let n=this._supportedAudioTypes.get(e.type);if(!n)continue;let i=e.toURL(t)??e.href;if(n===`probably`)return{href:i,type:e.type};r||={href:i,type:e.type,confidence:n}}return r?{href:r.href,type:r.type}:{href:e.toURL(t)??e.href,type:e.type}}get audioEngine(){return this._audioEngine}ensure(e){let t=this.pool.get(e);return t||(t=document.createElement(`audio`),t.preload=`auto`,this._audioEngine.isWebAudioActive&&(t.crossOrigin=`anonymous`),t.src=e,t.load(),this.pool.set(e,t)),t}update(e){if(this._audioEngine.usesMse)return;let t=this._publication.readingOrder.items,n=new Set;for(let r=0;r<t.length;r++){if(r===e)continue;let{href:i}=this.pickPlayableHref(t[r]);r>=e-1&&r<=e+1?(this.ensure(i),n.add(i)):r>=e-1&&r<=e+1&&this.pool.has(i)&&n.add(i)}for(let[e,t]of this.pool)n.has(e)||(t.removeAttribute(`src`),t.load(),this.pool.delete(e))}setCurrentAudio(e,t){let{href:n,type:r}=this.pickPlayableHref(this._publication.readingOrder.items[e]);if(this.audioEngine.changeSrc(n,r),this.pool.has(n)){let e=this.pool.get(n);e.removeAttribute(`src`),e.load(),this.pool.delete(n)}this.update(e)}destroy(){this.audioEngine.stop(),this.audioEngine.destroy();for(let[,e]of this.pool)e.removeAttribute(`src`),e.load();this.pool.clear()}},qf=class extends uu{constructor(e={}){super(e),e.disableDragAndDrop&&(this.dragAndDropProtector=new kf({onDragDetected:e=>{this.dispatchSuspiciousActivity(`drag_detected`,{dataTransferTypes:e,targetFrameSrc:``})},onDropDetected:(e,t)=>{this.dispatchSuspiciousActivity(`drop_detected`,{dataTransferTypes:e,fileCount:t,targetFrameSrc:``})}})),e.protectCopy&&(this.copyProtector=new Af({onCopyBlocked:()=>{this.dispatchSuspiciousActivity(`bulk_copy`,{targetFrameSrc:``})}}))}destroy(){super.destroy(),this.dragAndDropProtector?.destroy(),this.copyProtector?.destroy()}},Jf=e=>({trackLoaded:e.trackLoaded??(()=>{}),positionChanged:e.positionChanged??(()=>{}),timelineItemChanged:e.timelineItemChanged??(()=>{}),error:e.error??(()=>{}),trackEnded:e.trackEnded??(()=>{}),play:e.play??(()=>{}),pause:e.pause??(()=>{}),metadataLoaded:e.metadataLoaded??(()=>{}),stalled:e.stalled??(()=>{}),seeking:e.seeking??(()=>{}),seekable:e.seekable??(()=>{}),contentProtection:e.contentProtection??(()=>{}),peripheral:e.peripheral??(()=>{}),contextMenu:e.contextMenu??(()=>{}),remotePlaybackStateChanged:e.remotePlaybackStateChanged??(()=>{})}),Yf=class extends Nc{constructor(e,t,n,r={preferences:{},defaults:{}}){if(super(),this.positionPollInterval=null,this.navigationId=0,this._playIntent=!1,this._preferencesEditor=null,this._mediaSessionEnabled=!1,this._navigatorProtector=null,this._keyboardPeripheralsManager=null,this._suspiciousActivityListener=null,this._keyboardPeripheralListener=null,this._isNavigating=!1,this._isStalled=!1,this._destroyed=!1,this._stalledWatchdog=null,this._stalledCheckTime=0,this.pub=e,this.listeners=Jf(t),this._preferences=new Hf(r.preferences),this._defaults=new Uf(r.defaults),this._settings=new Wf(this._preferences,this._defaults),e.readingOrder.items.length===0)throw Error(`AudioNavigator: publication has an empty reading order`);if(n)this.currentLocation=this.ensureLocatorLocations(n);else{let e=this.pub.readingOrder.items[0];this.currentLocation=new j({href:e.href,type:e.type||`audio/mpeg`,title:e.title,locations:new k({position:1,progression:0,totalProgression:0,fragments:[`t=0`]})})}let i=this.currentLocation.href.split(`#`)[0],a=this.hrefToTrackIndex(i);if(a===-1){let e=this.currentLocation.locations?.totalProgression;if(e!==void 0){let t=this.locatorFromTotalProgression(e);this.currentLocation=t.locator,a=t.trackIndex}else throw Error(`AudioNavigator: initial href "${i}" not found in reading order`)}let o=Bt(this.currentLocation.locations)||0,s=new Vf({playback:{state:{currentTime:o,duration:0},playWhenReady:!1,index:a},mseLoaderFactory:r.mseLoaderFactory});this.pool=new Kf(s,e,r.contentProtection);let c=r.contentProtection||{};this._contentProtection=c;let l=this.mergeKeyboardPeripherals(c,r.keyboardPeripherals||[]);(c.disableContextMenu||c.checkAutomation||c.checkIFrameEmbedding||c.monitorDevTools||c.protectPrinting?.disable||c.disableDragAndDrop||c.protectCopy)&&(this._navigatorProtector=new qf(c),this._suspiciousActivityListener=e=>{let{type:t,...n}=e.detail;t===`context_menu`?this.listeners.contextMenu(n):this.listeners.contentProtection(t,n)},window.addEventListener(`readium:navigator:suspiciousActivity`,this._suspiciousActivityListener)),l.length>0&&(this._keyboardPeripheralsManager=new fu({keyboardPeripherals:l}),this._keyboardPeripheralListener=e=>{this.listeners.peripheral(e.detail)},window.addEventListener(`readium:navigator:keyboardPeripheral`,this._keyboardPeripheralListener)),this.setupEventListeners(),this._isNavigating=!0;let u=()=>this.startInitialLoad(a,o);if(r.mediaElementSetup){if(this._destroyed)return;Promise.resolve().then(()=>r.mediaElementSetup(this.pool.audioEngine.getMediaElement())).catch(e=>{this.listeners.error(e,this.currentLocator)}).then(u)}else u()}startInitialLoad(e,t){this._destroyed||(this.pool.setCurrentAudio(e,`forward`),this.applyPreferences(),this.waitForLoadedAndSeeked(t).then(()=>{this._isNavigating=!1,this.listeners.trackLoaded(this.pool.audioEngine.getMediaElement()),this._notifyTimelineChange(this.currentLocator),this.listeners.positionChanged(this.currentLocator),this._setupRemotePlayback()}).catch(()=>{this._isNavigating=!1}))}get settings(){return this._settings}get preferencesEditor(){return this._preferencesEditor===null&&(this._preferencesEditor=new Gf(this._preferences,this.settings)),this._preferencesEditor}async submitPreferences(e){this._preferences=this._preferences.merging(e),this.applyPreferences()}applyPreferences(){this._settings=new Wf(this._preferences,this._defaults),this._preferencesEditor!==null&&(this._preferencesEditor=new Gf(this._preferences,this.settings)),this.pool.audioEngine.setVolume(this._settings.volume),this.pool.audioEngine.setPlaybackRate(this._settings.playbackRate,this._settings.preservePitch),this.positionPollInterval!==null&&this.startPositionPolling(),this._settings.enableMediaSession&&!this._mediaSessionEnabled?(this._mediaSessionEnabled=!0,this.setupMediaSession()):!this._settings.enableMediaSession&&this._mediaSessionEnabled&&(this._mediaSessionEnabled=!1,this.destroyMediaSession())}get publication(){return this.pub}get timeline(){return this.pub.timeline}_notifyTimelineChange(e){let t=this.pub.timeline.locate(e);t!==this._currentTimelineItem&&(this._currentTimelineItem=t,this.listeners.timelineItemChanged(t),this._settings.enableMediaSession&&this.updateMediaSessionMetadata())}ensureLocatorLocations(e){return new j({...e,locations:e.locations instanceof k?e.locations:e.locations?new k(e.locations):void 0})}hrefToTrackIndex(e){let t=e.split(`#`)[0];return this.pub.readingOrder.items.findIndex(e=>e.href===t)}currentTrackIndex(){return this.hrefToTrackIndex(this.currentLocation.href)}locatorFromTotalProgression(e){let t=this.pub.readingOrder.items,n=t.map(e=>e.duration??0),r=n.reduce((e,t)=>e+t,0),i=0,a=0;if(r>0){let t=Math.min(Math.max(e,0),1)*r;for(let e=0;e<n.length;e++){if(i=e,t<=n[e]||e===n.length-1){a=t;break}t-=n[e]}}let o=t[i];return{trackIndex:i,locator:new j({href:o.href,type:o.type||``,title:o.title,locations:new k({position:i+1,progression:n[i]>0?a/n[i]:0,totalProgression:Math.min(Math.max(e,0),1),fragments:[`t=${a}`]})})}}get currentLocator(){return this.currentLocation}get isPlaying(){return this.pool.audioEngine.isPlaying()}get isPaused(){return this.pool.audioEngine.isPaused()}get duration(){return this.pool.audioEngine.duration()}get currentTime(){return this.pool.audioEngine.currentTime()}createLocator(e,t){let n=this.pub.readingOrder.items[e];if(!n)throw Error(`Invalid track index: ${e}`);let r=this.pool.audioEngine.duration();return new j({href:n.href,type:n.type||`audio/mpeg`,title:n.title,locations:new k({progression:r>0?t/r:0,position:e+1,fragments:[`t=${t}`]})})}waitForLoadedAndSeeked(e,t){return new Promise((n,r)=>{let i=()=>{if(t!==void 0&&t!==this.navigationId||e<=0){n();return}let r=()=>{this.pool.audioEngine.off(`seeked`,r),n()};this.pool.audioEngine.on(`seeked`,r),this.seek(e)};if(this.pool.audioEngine.isLoaded()){i();return}let a=()=>{this.pool.audioEngine.off(`canplaythrough`,a),this.pool.audioEngine.off(`error`,o),i()},o=e=>{this.pool.audioEngine.off(`canplaythrough`,a),this.pool.audioEngine.off(`error`,o),r(e)};this.pool.audioEngine.on(`canplaythrough`,a),this.pool.audioEngine.on(`error`,o)})}setupEventListeners(){this.pool.audioEngine.on(`error`,e=>{this.listeners.error(e,this.currentLocator)}),this.pool.audioEngine.on(`ended`,async()=>{this.stopPositionPolling(),this.currentLocation=this.currentLocation.copyWithLocations(new k({position:this.currentTrackIndex()+1,progression:1,fragments:[`t=${this.duration}`]})),this.listeners.trackEnded(this.currentLocator),this.canGoForward?(await this.nextTrack(),this._settings.autoPlay&&this.play()):this.listeners.positionChanged(this.currentLocator)}),this.pool.audioEngine.on(`play`,()=>{this._isNavigating||(this.startPositionPolling(),this.listeners.play(this.currentLocator))}),this.pool.audioEngine.on(`playing`,()=>{this._isNavigating||this._setStalled(!1)}),this.pool.audioEngine.on(`pause`,()=>{this._isNavigating||(this.stopPositionPolling(),this.listeners.pause(this.currentLocator))}),this.pool.audioEngine.on(`seeked`,()=>{if(this._isNavigating)return;this.listeners.seeking(!1);let e=this.currentTime,t=this.duration,n=t>0?e/t:0;this.currentLocation=this.currentLocation.copyWithLocations(new k({position:this.currentTrackIndex()+1,progression:n,fragments:[`t=${e}`]})),this._notifyTimelineChange(this.currentLocation),this.listeners.positionChanged(this.currentLocation)}),this.pool.audioEngine.on(`seeking`,()=>{this._isNavigating||this.listeners.seeking(!0)}),this.pool.audioEngine.on(`waiting`,()=>{this._isNavigating||this.listeners.seeking(!0)}),this.pool.audioEngine.on(`stalled`,()=>{this._isNavigating||this._setStalled(!0)}),this.pool.audioEngine.on(`canplaythrough`,()=>{this._isNavigating||this._setStalled(!1)}),this.pool.audioEngine.on(`progress`,e=>{this._isNavigating||this.listeners.seekable(e)}),this.pool.audioEngine.on(`loadedmetadata`,()=>{let e=this.pool.audioEngine.getMediaElement(),t={duration:this.pool.audioEngine.duration(),textTracks:e.textTracks,readyState:e.readyState,networkState:e.networkState};this.listeners.metadataLoaded(t)})}_setStalled(e){this._isStalled!==e&&(this._isStalled=e,this.listeners.stalled(e),e?(this._stalledCheckTime=this.currentTime,this._startStalledWatchdog()):this._stopStalledWatchdog())}_startStalledWatchdog(){this._stalledWatchdog=setInterval(()=>{if(!this.isPlaying){this._setStalled(!1);return}let e=this.currentTime;e!==this._stalledCheckTime&&this._setStalled(!1),this._stalledCheckTime=e},500)}_stopStalledWatchdog(){this._stalledWatchdog!==null&&(clearInterval(this._stalledWatchdog),this._stalledWatchdog=null)}setupMediaSession(){`mediaSession`in navigator&&(navigator.mediaSession.setActionHandler(`play`,()=>this.play()),navigator.mediaSession.setActionHandler(`pause`,()=>this.pause()),navigator.mediaSession.setActionHandler(`previoustrack`,()=>this.goBackward(!1,()=>{})),navigator.mediaSession.setActionHandler(`nexttrack`,()=>this.goForward(!1,()=>{})),navigator.mediaSession.setActionHandler(`seekbackward`,e=>this.jump(-(e.seekOffset||10))),navigator.mediaSession.setActionHandler(`seekforward`,e=>this.jump(e.seekOffset||10)),this.updateMediaSessionMetadata())}updateMediaSessionMetadata(){if(!(`mediaSession`in navigator))return;let e=this.currentTrackIndex(),t=this.pub.readingOrder.items[e],n=this.pub.getCover();navigator.mediaSession.metadata=new MediaMetadata({title:t?.title||`Track ${e+1}`,artist:this.pub.metadata.authors?this.pub.metadata.authors.items.map(e=>e.name.getTranslation()).join(`, `):void 0,album:this.pub.metadata.title.getTranslation(),artwork:n?[{src:n.toURL(this.pub.baseURL)??n.href,type:n.type}]:void 0})}startPositionPolling(){this.stopPositionPolling(),this.positionPollInterval=setInterval(()=>{let e=this.currentTime,t=this.duration,n=t>0?e/t:0;this.currentLocation=this.currentLocation.copyWithLocations(new k({position:this.currentTrackIndex()+1,progression:n,fragments:[`t=${e}`]})),this._notifyTimelineChange(this.currentLocation),this.listeners.positionChanged(this.currentLocation)},this._settings.pollInterval)}stopPositionPolling(){this.positionPollInterval!==null&&(clearInterval(this.positionPollInterval),this.positionPollInterval=null)}async go(e,t,n){try{e=this.ensureLocatorLocations(e);let t=e.href.split(`#`)[0],r=this.hrefToTrackIndex(t),i=Bt(e.locations)||0;if(r===-1){n(!1);return}let a=++this.navigationId,o=this.currentTrackIndex(),s=r>=o?`forward`:`backward`,c=this.isPlaying||this._playIntent;if(this._playIntent=c,this._isNavigating=!0,this.stopPositionPolling(),this.pool.setCurrentAudio(r,s),this.currentLocation=e.copyWithLocations(e.locations),await this.waitForLoadedAndSeeked(i,a),this._isNavigating=!1,a!==this.navigationId){n(!1);return}r!==o&&this.listeners.trackLoaded(this.pool.audioEngine.getMediaElement()),this._notifyTimelineChange(this.currentLocator),this.listeners.positionChanged(this.currentLocator),this._settings.enableMediaSession&&this.updateMediaSessionMetadata(),c&&this.play(),n(!0)}catch(e){this._isNavigating=!1,console.error(`Failed to go to locator:`,e),n(!1)}finally{this._playIntent=!1}}async goLink(e,t,n){let r=this.hrefToTrackIndex(e.href);if(r===-1){n(!1);return}let i=Bt(e.locator.locations)??0,a=this.createLocator(r,i);await this.go(a,t,n)}async goForward(e,t){this.canGoForward?(await this.nextTrack(),t(!0)):t(!1)}async goBackward(e,t){this.canGoBackward?(await this.previousTrack(),t(!0)):t(!1)}play(){this.pool.audioEngine.play()}pause(){this.pool.audioEngine.pause()}stop(){this.pool.audioEngine.stop()}async nextTrack(){if(!this.canGoForward)return;let e=this.createLocator(this.currentTrackIndex()+1,0);await this.go(e,!1,()=>{})}async previousTrack(){if(!this.canGoBackward)return;let e=this.createLocator(this.currentTrackIndex()-1,0);await this.go(e,!1,()=>{})}seek(e){this.pool.audioEngine.skip(e-this.pool.audioEngine.currentTime())}jump(e){this.pool.audioEngine.skip(e)}skipForward(){this.pool.audioEngine.skip(this._settings.skipForwardInterval)}skipBackward(){this.pool.audioEngine.skip(-this._settings.skipBackwardInterval)}get isTrackStart(){return this.currentTrackIndex()===0&&(Bt(this.currentLocation.locations)||0)===0}get isTrackEnd(){let e=this.currentTrackIndex();if(e!==this.pub.readingOrder.items.length-1)return!1;let t=this.currentLocation.locations?.progression;if(t!==void 0)return t>=1;let n=this.pub.readingOrder.items[e],r=this.duration||n?.duration||0;return r>0&&(Bt(this.currentLocation.locations)??0)>=r}get canGoBackward(){return this.currentTrackIndex()>0}get canGoForward(){return this.currentTrackIndex()<this.pub.readingOrder.items.length-1}get remotePlayback(){let e=this.pool.audioEngine.getMediaElement();return`remote`in e?e.remote:void 0}_setupRemotePlayback(){if(this._contentProtection.disableRemotePlayback)return;let e=this.remotePlayback;e&&(e.onconnecting=()=>this.listeners.remotePlaybackStateChanged(`connecting`),e.onconnect=()=>this.listeners.remotePlaybackStateChanged(`connected`),e.ondisconnect=()=>this.listeners.remotePlaybackStateChanged(`disconnected`))}destroyMediaSession(){`mediaSession`in navigator&&(navigator.mediaSession.metadata=null,navigator.mediaSession.setActionHandler(`play`,null),navigator.mediaSession.setActionHandler(`pause`,null),navigator.mediaSession.setActionHandler(`previoustrack`,null),navigator.mediaSession.setActionHandler(`nexttrack`,null),navigator.mediaSession.setActionHandler(`seekbackward`,null),navigator.mediaSession.setActionHandler(`seekforward`,null))}destroy(){this._destroyed=!0,this.stopPositionPolling(),this._stopStalledWatchdog(),this.destroyMediaSession(),this._suspiciousActivityListener&&window.removeEventListener(`readium:navigator:suspiciousActivity`,this._suspiciousActivityListener),this._keyboardPeripheralListener&&window.removeEventListener(`readium:navigator:keyboardPeripheral`,this._keyboardPeripheralListener),this._navigatorProtector?.destroy(),this._keyboardPeripheralsManager?.destroy(),this.pool.destroy()}},Xf=r({AudioDefaults:()=>Uf,AudioNavigator:()=>Yf,AudioPreferences:()=>Hf,AudioPreferencesEditor:()=>Gf,AudioSettings:()=>Wf,BUILTIN_DECORATION_TYPES:()=>Pc,BooleanPreference:()=>X,DecorationLayout:()=>cc,DecorationStyleType:()=>W,DecorationWidth:()=>sc,DivinaDefaults:()=>Pf,DivinaNavigator:()=>Rf,DivinaPage:()=>Qd,DivinaPageManager:()=>ff,DivinaPagedPresenter:()=>Df,DivinaPeripherals:()=>xf,DivinaPreferences:()=>Nf,DivinaPreferencesEditor:()=>If,DivinaQuality:()=>ef,DivinaScrolledPresenter:()=>Of,DivinaSettings:()=>Ff,DivinaSpreader:()=>$d,EnumPreference:()=>Nl,EpubDefaults:()=>Ku,EpubNavigator:()=>Zd,EpubPreferences:()=>Gu,EpubPreferencesEditor:()=>Ju,EpubSettings:()=>Wd,ExperimentalWebPubNavigator:()=>gu,FXLCoordinator:()=>Du,FXLFrameManager:()=>Nu,FXLFramePoolManager:()=>Wu,FXLPeripherals:()=>Mu,FXLSpreader:()=>Iu,FrameComms:()=>Uc,FrameManager:()=>xu,FramePoolManager:()=>wu,HorizontalThird:()=>Tu,Injector:()=>zl,LineLengths:()=>Jd,MOBILE_MAX_HEIGHT:()=>tf,MOBILE_MAX_WIDTH:()=>nf,MediaNavigator:()=>Nc,Navigator:()=>jc,Orientation:()=>Pu,Preference:()=>Y,Properties:()=>bl,RSProperties:()=>Qu,RangePreference:()=>Z,ReadiumCSS:()=>$u,Spread:()=>Fu,TextAlignment:()=>al,UserProperties:()=>Zu,VerticalThird:()=>Eu,VisualNavigator:()=>Mc,WebAudioEngine:()=>Vf,WebPubBlobBuilder:()=>Bc,WebPubCSS:()=>Cl,WebPubDefaults:()=>jl,WebPubFrameManager:()=>Kc,WebPubFramePoolManager:()=>qc,WebPubNavigator:()=>hu,WebPubPreferences:()=>Al,WebPubPreferencesEditor:()=>Pl,WebPubSettings:()=>Ml,WebRSProperties:()=>Sl,WebUserProperties:()=>xl,decorationsEqual:()=>zc,ensureBoolean:()=>K,ensureEnumValue:()=>El,ensureExperiment:()=>kl,ensureFilter:()=>Dl,ensureLessThanOrEqual:()=>wl,ensureMoreThanOrEqual:()=>Tl,ensureNonNegative:()=>q,ensureString:()=>G,ensureValueInRange:()=>J,experiments:()=>nl,filterRangeConfig:()=>ol,fontSizeRangeConfig:()=>sl,fontWeightRangeConfig:()=>cl,fontWidthRangeConfig:()=>ll,gatherVariants:()=>af,getScriptMode:()=>Qc,i18n:()=>il,isTypedOMSupported:()=>Q,letterSpacingRangeConfig:()=>ul,lineHeightRangeConfig:()=>dl,lineLengthRangeConfig:()=>fl,paragraphIndentRangeConfig:()=>pl,paragraphSpacingRangeConfig:()=>ml,placeholderSVG:()=>lf,playbackRateRangeConfig:()=>vl,resolveDecorationForWire:()=>Ic,selectVariant:()=>of,settings:()=>rl,skipIntervalRangeConfig:()=>yl,stripWidthRangeConfig:()=>Mf,supportsDecorationStyle:()=>Fc,volumeRangeConfig:()=>_l,withFallback:()=>Ol,wordSpacingRangeConfig:()=>hl,zoomRangeConfig:()=>gl}),Zf=`storyarc-highlights`,Qf=e=>e?{x:e.left,y:e.top,width:e.width,height:e.height}:void 0;function $f({navigator:e,post:t}){e.registerDecorationObserver(Zf,{onDecorationActivated:({decoration:e,rect:n})=>(t({type:`highlight-activated`,id:e.id,rect:Qf(n)}),!0)});function n(n){let r=n.flatMap(({id:e,locator:t,color:n})=>{let r=j.deserialize(t);return r?[{id:e,locator:r,style:{type:W.Highlight,tint:n}}]:[]});e.applyDecorations(r,Zf),t({type:`highlights`,ids:r.map(e=>e.id)})}function r(e){t({type:`selection`,text:e.text,locator:e.locator?.serialize(),rect:{x:e.x,y:e.y,width:e.width,height:e.height}})}return{apply:n,selected:r}}var ep=/^[a-z][a-z0-9+.-]*:/i,tp=/^https?:/i;function np(e){return(e.getAttribute(`epub:type`)??``).split(/\s+/).includes(`noteref`)||e.getAttribute(`role`)===`doc-noteref`}function rp(e,t){let n=new URL(e,`http://publication/${t}`);return`${decodeURIComponent(n.pathname.slice(1))}${n.hash}`}var ip=e=>e.replace(/\s+/g,` `).trim();function ap(e){for(let t of[`application/xhtml+xml`,`text/html`]){let n=new DOMParser().parseFromString(e,t);if(!n.querySelector(`parsererror`))return n}}function op({post:e,currentHref:t,readText:n}){async function r(e,r){let i=t(),a=e.startsWith(`#`)?`${i}${e}`:rp(e,i),[o,s]=a.split(`#`),c=o===i?r:void 0;if(!c){let e=await n(o).catch(()=>void 0);c=e===void 0?void 0:ap(e)}let l=s?c?.getElementById(decodeURIComponent(s)):void 0;return{href:a,text:l?ip(l.textContent??``):``}}function i(t){let n=t.target?.closest?.(`a[href]`);if(!n)return;let i=n.getAttribute(`href`),a=()=>{t.preventDefault(),t.stopImmediatePropagation()};np(n)&&!ep.test(i)?(a(),r(i,n.ownerDocument).then(({href:t,text:n})=>e({type:`footnote`,href:t,text:n}))):ep.test(i)&&(a(),tp.test(i)&&e({type:`link`,href:new URL(i).href}))}let a=new WeakSet;function o(e){a.has(e)||(a.add(e),e.addEventListener(`click`,i,!0))}function s(t){return tp.test(t.href)&&e({type:`link`,href:t.href}),!0}return{attach:o,handleLocator:s}}var sp=40,cp=500,lp=e=>e.normalize(`NFD`).replace(/\p{M}/gu,``).toLowerCase();function up(e){let t=``,n=[],r=!1;for(let i=0;i<e.length;i+=1){let a=e[i];if(/\s/u.test(a))!r&&t!==``&&(t+=` `,n.push(i)),r=!0;else{r=!1;for(let e of lp(a))t+=e,n.push(i)}}return{folded:t,origin:n}}var dp=e=>e.replace(/\s+/g,` `);function fp(e,t,{limit:n=cp}={}){let r=up(t.trim()).folded;if(r===``)return[];let{folded:i,origin:a}=up(e),o=[];for(let t=i.indexOf(r);t!==-1&&o.length<n;t=i.indexOf(r,t+r.length)){let n=a[t],i=a[t+r.length-1]+1;o.push({start:n,end:i,before:dp(e.slice(Math.max(0,n-sp),n)).trimStart(),highlight:dp(e.slice(n,i)),after:dp(e.slice(i,i+sp)).trimEnd(),progression:e.length===0?0:n/e.length})}return o}function pp(e){for(let t of[`application/xhtml+xml`,`text/html`]){let n=new DOMParser().parseFromString(e,t);if(!n.querySelector(`parsererror`)){for(let e of n.querySelectorAll(`script, style, head`))e.remove();return n.documentElement.textContent??``}}return``}function mp({chapters:e,readText:t,locate:n,post:r}){let i=0;async function a(a,o){i+=1;let s=i,c=()=>i===s,l=0;if(o.trim()!==``)for(let i of e){if(!c()||l>=cp)break;let e=await t(i.href).catch(()=>void 0);if(!c())return;if(e===void 0)continue;let s=fp(pp(e),o,{limit:cp-l});s.length!==0&&(l+=s.length,r({type:`search-results`,id:a,done:!1,results:s.map(e=>({locator:{...n(i.href,e.progression),text:{before:e.before,highlight:e.highlight,after:e.after}}}))}))}c()&&r({type:`search-results`,id:a,done:!0,total:l,truncated:l>=cp,results:[]})}return{start:a}}var hp=`storyarc`;function gp(e=globalThis){let t=e.webkit?.messageHandlers?.[hp];if(t)return e=>t.postMessage(e);let n=e.chrome?.webview;return n?e=>n.postMessage(e):()=>{}}function _p(e){let t=0;return n=>{t+=1,e({...n,seq:t})}}var vp=Object.freeze({});function yp(e){let t=e._css;return{...t.rsProperties.toCSSProperties(),...t.userProperties.toCSSProperties()}}var bp=`.readium-navigator-iframe { border: 0; width: 100%; height: 100%; }`;function xp(e){let t=e.ownerDocument,n=t.createElement(`div`);if(n.style.height=`100%`,e.append(n),`adoptedStyleSheets`in t&&`replaceSync`in CSSStyleSheet.prototype){let e=new CSSStyleSheet;e.replaceSync(bp),t.adoptedStyleSheets=[...t.adoptedStyleSheets,e]}else{let e=t.createElement(`style`);e.textContent=bp,t.head.append(e)}return n}var Sp=e=>new Promise(t=>e(t));async function Cp({container:e,manifest:t,positions:n=[],locator:r,preferences:i={},post:o}){let s=_p(o??gp()),c=ma.deserialize(t);if(!c)throw Error(`the manifest is not a Readium Web Publication Manifest`);let l=new ya({manifest:c}).baseURL,u=new ya({manifest:c,fetcher:new a(void 0,l)}),d=n.map(e=>j.deserialize(e)).filter(Boolean),f=r?j.deserialize(r):void 0,p,m=op({post:s,currentHref:()=>p.currentLocator.href,readText:e=>u.get(new M({href:e})).readAsString()}),h={...i},g;p=new Zd(xp(e),u,{frameLoaded:e=>m.attach(e),positionChanged:e=>s({type:`locator`,locator:e.serialize()}),handleLocator:m.handleLocator,textSelected:e=>g.selected(e)},d,f,{preferences:new Gu(h),defaults:vp}),g=$f({navigator:p,post:s}),await p.load(),s({type:`ready`,title:t.metadata?.title,positions:d.length});async function ee(e){h={...h,...e},await p.submitPreferences(new Gu(h)),s({type:`preferences`,properties:yp(p)})}async function te({theme:e}){let t={...Object.fromEntries(Object.keys(h).map(e=>[e,null])),...e.axes};h=Object.fromEntries(Object.entries(t).filter(([,e])=>e!==null)),await p.submitPreferences(new Gu(t)),s({type:`theme`,name:e.name,background:e.axes.backgroundColor,text:e.axes.textColor,properties:yp(p)})}function _(e,t){let n=u.readingOrder.findWithHref(e),r=d.filter(t=>t.href===e),i=[...r].reverse().find(e=>(e.locations.progression??0)<=t)??r[0];return{href:e,type:n?.type??`application/xhtml+xml`,title:n?.title,locations:{progression:t,position:i?.locations.position,totalProgression:i?.locations.totalProgression}}}let v=mp({chapters:u.readingOrder.items,readText:e=>u.get(new M({href:e})).readAsString(),locate:_,post:s}),y={theme:te,search:({id:e,query:t})=>v.start(e,String(t??``)),highlights:({items:e})=>g.apply(e??[]),async go({locator:e}){let t=j.deserialize(e);if(!t)return s({type:`navigation-failed`,reason:`not a locator`});await Sp(e=>p.go(t,!1,e))||s({type:`navigation-failed`,reason:`not reachable`})},async next(){await Sp(e=>p.goForward(!1,e))},async previous(){await Sp(e=>p.goBackward(!1,e))},preferences:({preferences:e})=>ee(e??{})};return{navigator:p,publication:u,receive:e=>y[e?.type]?.(e),destroy:async()=>{await p.destroy(),e.replaceChildren()}}}return e.hostPost=gp,Object.defineProperty(e,"navigator",{enumerable:!0,get:function(){return Xf}}),e.open=Cp,Object.defineProperty(e,"shared",{enumerable:!0,get:function(){return ba}}),e})({});