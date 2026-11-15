// clock-status: the bar's two-line clock (time over date, full date in the
// tooltip) as waybar JSON. Waybar runs it every 10 seconds
// (config/waybar/config.jsonc, "custom/clock").
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"time"
)

type format struct {
	Text    string `json:"text"`
	Tooltip string `json:"tooltip"`
}

func main() {
	dateTime, err := clock(time.Now())
	if err != nil {
		fmt.Fprintf(os.Stderr, "%v\n", err)
		os.Exit(1)
	}

	fmt.Printf("%s", dateTime)
}

// The bar's clock for timeNow, as waybar JSON
func clock(timeNow time.Time) ([]byte, error) {
	// Taller line heights push the date out of the bar
	currentTime := fmt.Sprintf("<span size='10pt' line_height='0.85' weight='600'>%s</span>", timeNow.Format("15:04"))

	dateNow := fmt.Sprintf("<span size='7.5pt' alpha='80%%' line_height='0.85'>%s</span>", timeNow.Format("Mon Jan 2"))

	tooltip := timeNow.Format("Monday, 02 January 2006")

	return json.Marshal(format{Text: fmt.Sprintf("%s\n%s", currentTime, dateNow), Tooltip: tooltip})
}
