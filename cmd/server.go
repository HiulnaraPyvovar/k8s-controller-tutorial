package cmd

import (
	"fmt"
	"os"

	"github.com/rs/zerolog/log"
	"github.com/spf13/cobra"
	"github.com/valyala/fasthttp"
)

var serverPort int

var serverCmd = &cobra.Command{
	Use:   "server",
	Short: "Start FastHTTP server",
	Long:  `Start a FastHTTP server that listens on the specified port.`,
	Run: func(cmd *cobra.Command, args []string) {
		handler := func(ctx *fasthttp.RequestCtx) {
			fmt.Fprintf(ctx, "Welcome to the FastHTTP server")
		}
		addr := fmt.Sprintf(":%d", serverPort)
		log.Info().Msgf("Starting FastHTTP server on %s", addr)
		if err := fasthttp.ListenAndServe(addr, handler); err != nil {
			log.Error().Err(err).Msg("Failed to start FastHTTP server")
			os.Exit(1)
		}
	},
}

func init() {
	rootCmd.AddCommand(serverCmd)
	serverCmd.Flags().IntVar(&serverPort, "port", 8080, "Port to run the FastHTTP server on")
}
