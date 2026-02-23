import { LightningElement, api, track } from 'lwc';

export default class JSONViewer extends LightningElement {
    @track formattedJSON = '';
    @api jsoninput = '';

    handlePrettify() {
        const inputJsonField = this.refs.inputArea.value;
        if (inputJsonField) {
            this.formattedJSON = '<html><style>ul, #myUL {list-style-type: none;}#myUL {margin: 0;padding: 0;}.caret {cursor: pointer;-webkit-user-select: none; /* Safari 3.1+ */-moz-user-select: none; /* Firefox 2+ */-ms-user-select: none; /* IE 10+ */user-select: none;}.caret::before {content: "\\1f53d";color: black;display: inline-block;margin-right: 6px;}.caret-down::before {transform: rotate(-90deg);  }.nested {display: block;margin-left:30px;}.active {display: none;}</style>';
            this.formattedJSON += this.processJsonObject(JSON.parse(inputJsonField));
            this.formattedJSON += '</html>';

            if (this.formattedJSON) {
                const container = this.template.querySelector('.json-container');
                container.innerHTML = this.formattedJSON;
            }

            var toggler = document.getElementsByClassName("caret");
            var i;

            for (i = 0; i < toggler.length; i++) {
                toggler[i].addEventListener("click", function () {
                    this.parentElement.querySelector(".nested").classList.toggle("active");
                    this.classList.toggle("caret-down");
                });
            }
        } else {
            this.formattedJSON = '';
        }

    }

    processJsonObject(jsonData) {
        let html = '<ul style="list-style-type: none;margin: 0; padding: 0;">';
        for (const key in jsonData) {
            if (Array.isArray(jsonData[key])) {
                html += `<li style="font-size:1rem;margin-top:.25rem;margin-bottom:.25rem;"><span class="caret">${key}</span><ul class="nested">${this.processJsonObject(jsonData[key])}</ul></li>`;
            } else if (typeof jsonData[key] === 'object') {
                html += `<li style="font-size:1rem;margin-top:.25rem;margin-bottom:.25rem;"><span class="caret">${key}</span><ul class="nested">${this.processJsonObject(jsonData[key])}</ul></li>`;
            } else {
                html += `<li style="font-size:1rem;margin-left:10px; margin-top:.25rem;margin-bottom:.25rem;">${'<b>' + key + '</b>' + ' : ' + jsonData[key]}</li>`;
            }
        }
        html += '</ul>';
        return html;

    }

    processJsonArray(jsonArray) {
        let html = '<ul style="list-style-type: none; margin: 0; padding: 0;">';

        for (const item of jsonArray) {
            html += '<li style="font-size:1rem;">{</li>';
            html += `<li style="font-size:1rem;"><ul class="nested">${this.processJsonObject(item)}</ul></li>`;
            html += '<li style="font-size:1rem;">}</li>';
        }

        html += '</ul>';
        return html;
    }


}