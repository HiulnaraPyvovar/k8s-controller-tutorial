package cmd

import (
	"context"
	"fmt"
	"os"

	"github.com/rs/zerolog/log"
	"github.com/spf13/cobra"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/tools/clientcmd"
)

var kubeconfig string

var listCmd = &cobra.Command{
	Use:   "list",
	Short: "List Kubernetes deployments in the default namespace",
	Long:  `List all Kubernetes deployments in the default namespace using the provided kubeconfig file.`,
	Run: func(cmd *cobra.Command, args []string) {
		clientset, err := getKubeClient(kubeconfig)
		if err != nil {
			log.Error().Err(err).Msg("Failed to create Kubernetes client")
			os.Exit(1)
		}
		deployments, err := clientset.AppsV1().Deployments("default").List(context.Background(), metav1.ListOptions{})
		if err != nil {
			log.Error().Err(err).Msg("Failed to list deployments")
			os.Exit(1)
		}
		fmt.Printf("Found %d deployments in 'default' namespace:\n", len(deployments.Items))
		for _, d := range deployments.Items {
			fmt.Println("-", d.Name)
		}
	},
}

func getKubeClient(kubeconfigPath string) (*kubernetes.Clientset, error) {
	config, err := clientcmd.BuildConfigFromFlags("", kubeconfigPath)
	if err != nil {
		return nil, err
	}
	return kubernetes.NewForConfig(config)
}

func init() {
	rootCmd.AddCommand(listCmd)
	listCmd.Flags().StringVar(&kubeconfig, "kubeconfig", "", "Path to the kubeconfig file")
}